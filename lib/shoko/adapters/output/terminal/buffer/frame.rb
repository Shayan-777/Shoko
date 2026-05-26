# frozen_string_literal: true

require_relative 'frame_write_support'
require_relative 'frame_render_support'

module Shoko
  module Adapters
    module Output
      module Terminal
        class TerminalBuffer
          # In-memory frame buffer storing characters and style runs.
          class Frame
            include FrameWriteSupport
            include FrameRenderSupport

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

            def initialize(width, height, runtime_config:)
              unless runtime_config.is_a?(Shoko::Application::Ports::Outbound::RuntimeConfig)
                raise ArgumentError, 'runtime_config must implement Application::Ports::Outbound::RuntimeConfig'
              end

              @width = width.to_i
              @height = height.to_i
              @runtime_config = runtime_config
              @chars = Array.new(@height) { Array.new(@width, ' ') }
              @styles = Array.new(@height) { Array.new(@width, nil) }
            end

            def write(row, col, text)
              return if @width <= 0 || @height <= 0

              context = WriteContext.new(self, row.to_i - 1, col.to_i - 1)
              return unless context.valid?

              source = normalize_input_text(text)
              if fast_ascii_writable?(source)
                fast_write_ascii(context, source)
              else
                process_tokens(context, source)
              end
            end
          end
        end
      end
    end
  end
end
