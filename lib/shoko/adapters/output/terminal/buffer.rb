# frozen_string_literal: true

require_relative 'output'
require_relative 'text_metrics'
require_relative '../../runtime/null_runtime_config'

module Shoko
  module Adapters
    module Output
      module Terminal
        # TerminalBuffer manages buffered writes and differential screen updates.
        class TerminalBuffer
          # In-memory frame buffer storing characters and style runs.
          class Frame
            CONTINUATION = :_wide_continuation
            CONTROL_CHAR_PATTERN = /[\u0000-\u001F\u007F-\u009F]/
            FAST_ASCII_WRITE_ENABLED_KEY = :shoko_fast_ascii_frame_write_enabled

            attr_reader :width, :height

            class << self
              def with_fast_ascii_write(enabled:)
                previous = Thread.current[FAST_ASCII_WRITE_ENABLED_KEY]
                Thread.current[FAST_ASCII_WRITE_ENABLED_KEY] = enabled ? true : false
                yield
              ensure
                Thread.current[FAST_ASCII_WRITE_ENABLED_KEY] = previous
              end
            end

            def initialize(width, height, runtime_config: nil)
              @width = width.to_i
              @height = height.to_i
              @runtime_config = runtime_config || Shoko::Adapters::Runtime::NullRuntimeConfig.instance
              @chars = Array.new(@height) { Array.new(@width, ' ') }
              @styles = Array.new(@height) { Array.new(@width, nil) }
            end

            def write(row, col, text)
              return if @width <= 0 || @height <= 0

              context = WriteContext.new(self, row.to_i - 1, col.to_i - 1)
              return unless context.valid?

              source = text.to_s
              if fast_ascii_writable?(source)
                fast_write_ascii(context, source)
              else
                process_tokens(context, source)
              end
            rescue Shoko::Error
              nil
            end

            # Encapsulates write operation state
            WriteContext = Struct.new(:frame, :row, :col_pos, :current_style) do
              def initialize(frame, row, col)
                super(frame, row, col, '')
              end

              def valid?
                return false if row.negative? || row >= frame.height
                return false if col_pos.negative? || col_pos >= frame.width

                true
              end

              def width
                frame.width
              end

              def at_end?
                col_pos >= width
              end

              def advance(amount = 1)
                self.col_pos += amount
              end

              def style_value
                current_style.empty? ? nil : current_style
              end
            end

            private

            def process_tokens(context, text)
              String(text).scan(TextMetrics::TOKEN_REGEX).each do |token|
                break if context.at_end?

                result = process_single_token(context, token)
                break if result == :stop
              end
            end

            def fast_ascii_writable?(source)
              return false unless fast_ascii_write_enabled?
              return false if source.empty?
              return false unless source.ascii_only?
              return false if source.include?("\e") || source.include?("\t")
              return false if source.include?("\n") || source.include?("\r")

              !source.match?(CONTROL_CHAR_PATTERN)
            end

            def fast_ascii_write_enabled?
              override = Thread.current[FAST_ASCII_WRITE_ENABLED_KEY]
              return override unless override.nil?

              !@runtime_config.fast_ascii_frame_write_disabled?
            end

            def fast_write_ascii(context, source)
              available = @width - context.col_pos
              return if available <= 0

              length = [source.bytesize, available].min
              slice = source.byteslice(0, length)
              row = context.row
              col = context.col_pos
              chars = @chars[row]
              styles = @styles[row]

              idx = 0
              while idx < length
                pos = col + idx
                clear_wide_overlap(row, pos)
                chars[pos] = slice.getbyte(idx).chr
                styles[pos] = nil
                idx += 1
              end

              context.advance(length)
            end

            def process_single_token(context, token)
              return process_ansi_sequence(context, token) if token.start_with?("\e[")
              return :skip if token == "\e"
              return process_tab(context) if token == "\t"

              process_printable(context, token)
            end

            def process_ansi_sequence(context, token)
              return :skip unless token.end_with?('m')

              if token == TerminalOutput::ANSI::RESET
                context.current_style = ''
              else
                context.current_style += token
              end
              :skip
            end

            def process_tab(context)
              tab_size = TextMetrics::TAB_SIZE
              spaces = tab_size - (context.col_pos % tab_size)

              spaces.times do
                break if context.at_end?

                write_cell(context.row, context.col_pos, ' ', context.style_value)
                context.advance
              end
              :continue
            end

            def process_printable(context, token)
              cluster = normalize_cluster(token)
              return :skip unless cluster

              char_width = TextMetrics.display_width_for(cluster)
              return :skip if char_width <= 0
              return :stop if char_width > (@width - context.col_pos)

              write_cluster(context, cluster, char_width)
              :continue
            end

            def normalize_cluster(token)
              return ' ' if ["\n", "\r"].include?(token)
              return nil if token.match?(CONTROL_CHAR_PATTERN)

              token
            end

            def write_cluster(context, cluster, char_width)
              write_cell(context.row, context.col_pos, cluster, context.style_value)
              write_continuation_cells(context, char_width) if char_width > 1
              context.advance(char_width)
            end

            def write_cell(row_i, col_i, char, style)
              clear_wide_overlap(row_i, col_i)
              @chars[row_i][col_i] = char
              @styles[row_i][col_i] = style
            end

            def write_continuation_cells(context, char_width)
              (1...char_width).each do |delta|
                pos = context.col_pos + delta
                break if pos >= @width

                clear_wide_overlap(context.row, pos)
                @chars[context.row][pos] = CONTINUATION
                @styles[context.row][pos] = nil
              end
            end

            public

            def rendered_rows
              (0...@height).map { |row_i| render_row(row_i) }
            end

            private

            def clear_wide_overlap(row_i, col_i)
              cell = @chars[row_i][col_i]
              if cell == CONTINUATION && col_i.positive?
                @chars[row_i][col_i - 1] = ' '
                @styles[row_i][col_i - 1] = nil
              elsif col_i + 1 < @width && @chars[row_i][col_i + 1] == CONTINUATION
                @chars[row_i][col_i + 1] = ' '
                @styles[row_i][col_i + 1] = nil
              end
              @chars[row_i][col_i] = ' '
              @styles[row_i][col_i] = nil
            end

            def render_row(row_i)
              chars = @chars[row_i]
              styles = @styles[row_i]
              last_col = last_non_blank_col(chars, styles)
              return '' if last_col.negative?

              out = +''
              active_style = nil
              run = +''

              col = 0
              while col <= last_col
                ch = chars[col]
                if ch == CONTINUATION
                  col += 1
                  next
                end

                style = styles[col]
                style = nil if style.nil? || style.empty?

                if style != active_style
                  flush_run(out, run, active_style)
                  run = +''
                  active_style = style
                end

                run << (ch || ' ')
                col += 1
              end

              flush_run(out, run, active_style)
              out
            end

            def last_non_blank_col(chars, styles)
              idx = chars.length - 1
              while idx >= 0
                ch = chars[idx]
                style = styles[idx]
                return idx if ch == CONTINUATION
                return idx if style && !style.empty?
                return idx if ch && ch != ' '

                idx -= 1
              end
              -1
            end

            def flush_run(out, run, style)
              return if run.empty?

              if style
                out << style << run << TerminalOutput::ANSI::RESET
              else
                out << run
              end
            end
          end

          attr_reader :buffer

          def initialize(output = TerminalOutput.new, runtime_config: nil)
            @output = output
            @runtime_config = runtime_config || Shoko::Adapters::Runtime::NullRuntimeConfig.instance
            @buffer = []
            @batch_mode = false
            @batch_buffer = nil
            @frame = nil
            @previous_rows = []
            @raw_sequences = []
            @width = 0
            @height = 0
          end

          def start_frame(width:, height:, runtime_config: nil)
            @runtime_config = runtime_config if runtime_config
            @raw_sequences = []
            @buffer = []

            width_i = width.to_i
            height_i = height.to_i
            width_i = 0 if width_i.negative?
            height_i = 0 if height_i.negative?

            size_changed = (width_i != @width) || (height_i != @height)
            @width = width_i
            @height = height_i
            @previous_rows = Array.new(@height) if size_changed
            @frame = Frame.new(@width, @height, runtime_config: @runtime_config)
          end

          def end_frame
            flush_frame
            @output.flush
          end

          def raw(text)
            return unless text

            if @batch_mode
              @batch_buffer << text.to_s
            else
              @raw_sequences << text.to_s
            end
          end

          def write(row, col, text)
            if @frame
              @frame.write(row, col, text)
              return
            end

            content = TerminalOutput::ANSI.move(row, col) + text.to_s
            @output.print(content)
          end

          def write_differential(row, col, text)
            write(row, col, text)
          end

          def clear_buffer_cache
            @previous_rows = Array.new(@height)
          end

          def batch_write
            @batch_mode = true
            @batch_buffer = []
            yield
            @output.print(@batch_buffer.join)
            @output.flush
          ensure
            @batch_mode = false
            @batch_buffer = nil
          end

          private

          def flush_frame
            return unless @frame

            rendered = @frame.rendered_rows
            out = +''
            @raw_sequences.each { |seq| out << seq }

            rendered.each_with_index do |row_text, idx|
              prev = @previous_rows[idx]
              next if prev == row_text

              row_number = idx + 1
              out << TerminalOutput::ANSI.move(row_number, 1)
              out << TerminalOutput::ANSI.clear_line
              out << row_text unless row_text.empty?
              @previous_rows[idx] = row_text
            end

            @output.print(out) unless out.empty?
          ensure
            @frame = nil
            @raw_sequences = []
          end
        end
      end
    end
  end
end
