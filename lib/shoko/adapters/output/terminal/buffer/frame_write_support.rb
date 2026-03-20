# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Terminal
        class TerminalBuffer
          class Frame
            # Tokenization, ANSI handling, and cell writes for terminal frame buffers.
            module FrameWriteSupport
              private

              def process_tokens(context, text)
                String(text).scan(TextMetrics::TOKEN_REGEX).each do |token|
                  break if context.at_end?

                  result = process_single_token(context, token)
                  break if result == :stop
                end
              end

              def normalize_input_text(text)
                source = text.to_s
                return source if source.encoding == Encoding::UTF_8 && source.valid_encoding?

                source.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
              rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError, Encoding::CompatibilityError
                source
                  .dup
                  .force_encoding(Encoding::BINARY)
                  .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
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
                slice = writable_ascii_slice(context, source)
                return unless slice

                write_ascii_slice(context, slice)
                context.advance(slice.bytesize)
              end

              def writable_ascii_slice(context, source)
                available = @width - context.col_pos
                return nil if available <= 0

                length = [source.bytesize, available].min
                source.byteslice(0, length)
              end

              def write_ascii_slice(context, slice)
                row = context.row
                col = context.col_pos
                buffers = { chars: @chars[row], styles: @styles[row] }

                slice.bytes.each_with_index do |byte, index|
                  write_ascii_cell(buffers, row, col + index, byte)
                end
              end

              def write_ascii_cell(buffers, row, col, byte)
                clear_wide_overlap(row, col)
                buffers[:chars][col] = byte.chr
                buffers[:styles][col] = nil
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
                spaces_to_next_tab_stop(context).times do
                  break if context.at_end?

                  write_cell(context.row, context.col_pos, ' ', context.style_value)
                  context.advance
                end
                :continue
              end

              def spaces_to_next_tab_stop(context)
                TextMetrics::TAB_SIZE - (context.col_pos % TextMetrics::TAB_SIZE)
              end

              def process_printable(context, token)
                cluster = normalize_cluster(token)
                return :skip unless cluster

                char_width = TextMetrics.display_width_for(cluster)
                return :skip if char_width <= 0
                return :stop if char_width > remaining_width(context)

                write_cluster(context, cluster, char_width)
                :continue
              end

              def normalize_cluster(token)
                return ' ' if ["\n", "\r"].include?(token)
                return nil if token.match?(CONTROL_CHAR_PATTERN)

                token
              end

              def remaining_width(context)
                @width - context.col_pos
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

              def clear_wide_overlap(row_i, col_i)
                clear_left_overlap(row_i, col_i)
                clear_right_overlap(row_i, col_i)
                clear_cell(row_i, col_i)
              end

              def clear_left_overlap(row_i, col_i)
                return unless @chars[row_i][col_i] == CONTINUATION && col_i.positive?

                clear_cell(row_i, col_i - 1)
              end

              def clear_right_overlap(row_i, col_i)
                return unless col_i + 1 < @width && @chars[row_i][col_i + 1] == CONTINUATION

                clear_cell(row_i, col_i + 1)
              end

              def clear_cell(row_i, col_i)
                @chars[row_i][col_i] = ' '
                @styles[row_i][col_i] = nil
              end
            end
          end
        end
      end
    end
  end
end
