# frozen_string_literal: true

require_relative 'output'
require_relative 'text_metrics'
require_relative 'buffer/frame'
require 'shoko/application/ports/outbound/runtime_config'

module Shoko
  module Adapters
    module Output
      module Terminal
        # TerminalBuffer manages buffered writes and differential screen updates.
        class TerminalBuffer
          attr_reader :buffer

          def initialize(output = TerminalOutput.new, runtime_config:)
            unless runtime_config.is_a?(Shoko::Application::Ports::Outbound::RuntimeConfig)
              raise ArgumentError, 'runtime_config must implement Application::Ports::Outbound::RuntimeConfig'
            end

            @output = output
            @runtime_config = runtime_config
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
            apply_runtime_config!(runtime_config) if runtime_config
            reset_frame_buffers

            width_i, height_i = normalized_frame_size(width, height)
            update_frame_size(width_i, height_i)
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

          def apply_runtime_config!(runtime_config)
            unless runtime_config.is_a?(Shoko::Application::Ports::Outbound::RuntimeConfig)
              raise ArgumentError, 'runtime_config must implement Application::Ports::Outbound::RuntimeConfig'
            end

            @runtime_config = runtime_config
          end

          def reset_frame_buffers
            @raw_sequences = []
            @buffer = []
          end

          def normalized_frame_size(width, height)
            width_i = width.to_i
            height_i = height.to_i
            [width_i.negative? ? 0 : width_i, height_i.negative? ? 0 : height_i]
          end

          def update_frame_size(width_i, height_i)
            size_changed = (width_i != @width) || (height_i != @height)
            @width = width_i
            @height = height_i
            @previous_rows = Array.new(@height) if size_changed
          end

          def flush_frame
            return unless @frame

            output = rendered_frame_output(@frame.rendered_rows)
            @output.print(output) unless output.empty?
          ensure
            clear_frame_state
          end

          def rendered_frame_output(rendered_rows)
            out = +''
            append_raw_sequences(out)
            append_changed_rows(out, rendered_rows)
            out
          end

          def append_raw_sequences(out)
            @raw_sequences.each { |sequence| out << sequence }
          end

          def append_changed_rows(out, rendered_rows)
            rendered_rows.each_with_index do |row_text, index|
              append_changed_row(out, index, row_text)
            end
          end

          def append_changed_row(out, index, row_text)
            previous = @previous_rows[index]
            return if previous == row_text

            row_number = index + 1
            out << TerminalOutput::ANSI.move(row_number, 1)
            out << TerminalOutput::ANSI.clear_line
            out << row_text unless row_text.empty?
            @previous_rows[index] = row_text
          end

          def clear_frame_state
            @frame = nil
            @raw_sequences = []
          end
        end
      end
    end
  end
end
