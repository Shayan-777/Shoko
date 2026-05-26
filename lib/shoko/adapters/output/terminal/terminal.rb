# frozen_string_literal: true

require 'io/console'
require_relative 'constants/terminal_defaults'
require_relative 'output'
require_relative 'buffer'
require_relative 'input'
require_relative 'null_runtime_config'
require_relative '../../../application/ports/outbound/runtime_config'

module Shoko
  module Adapters
    module Output
      module Terminal
        # Facade that preserves the historical Terminal API
        # while delegating to composable, testable components:
        # - TerminalOutput
        # - TerminalBuffer
        # - TerminalInput
        class Terminal
          # Keep ANSI nested under Terminal for compatibility
          ANSI = TerminalOutput::ANSI

          # Defines constants for special keyboard keys to abstract away different
          # terminal escape codes.
          module Keys
            UP = ["\e[A", "\eOA", 'k'].freeze
            DOWN = ["\e[B", "\eOB", 'j'].freeze
            ENTER = ["\r", "\n"].freeze
            ESCAPE = ["\e", "\x1B", 'q'].freeze
          end

          @runtime_config = Shoko::Adapters::Output::Terminal::NullRuntimeConfig.instance
          @output = TerminalOutput.new($stdout)
          @buffer_manager = TerminalBuffer.new(@output, runtime_config: @runtime_config)
          @input = TerminalInput.new
          @buffer = @buffer_manager.buffer
          @color_mode = nil

          class << self
            # Expose a print wrapper for backward-compatible expectations in tests
            def print(str)
              @output.print(str)
            end

            def size
              @input.size
            end

            def clear
              print [ANSI::Control::CLEAR, ANSI::Control::HOME].join
              clear_buffer_cache
              $stdout.flush
            end

            def move(row, col)
              # Historically this only queued the move; keep parity
              @buffer << ANSI.move(row, col)
            end

            def write(row, col, text)
              @buffer_manager.write(row, col, text)
            end

            def write_differential(row, col, text)
              @buffer_manager.write_differential(row, col, text)
            end

            def clear_buffer_cache
              @buffer_manager.clear_buffer_cache
            end

            def batch_write(&)
              @buffer_manager.batch_write(&)
            end

            def start_frame(width: nil, height: nil, runtime_config: nil)
              configure_runtime_config(runtime_config) if runtime_config
              if width && height
                w = width.to_i
                h = height.to_i
              else
                h, w = size
              end

              @buffer_manager.start_frame(width: w, height: h, runtime_config: @runtime_config)
              @buffer = @buffer_manager.buffer
            end

            def end_frame
              @buffer_manager.end_frame
            end

            # Queue raw control sequences (e.g., Kitty graphics) for the current frame.
            # These are emitted before any row diffs.
            def raw(text)
              @buffer_manager.raw(text)
            end

            def setup
              @input.setup_console
              print ANSI::Control::SAVE_SCREEN
              print ANSI::Control::HIDE_CURSOR
              print ANSI::DEFAULT_BG
              clear
              @input.setup_signal_handlers { cleanup }
              refresh_color_mode
            end

            def cleanup
              @input&.drain_input
              print([
                ANSI::Control::CLEAR,
                ANSI::Control::HOME,
                ANSI::Control::SHOW_CURSOR,
                ANSI::Control::RESTORE_SCREEN,
                ANSI::RESET,
              ].join)
              @output.flush
              @input.cleanup_console
            end

            def read_key
              @input.read_key
            end

            def read_key_blocking(timeout: nil)
              @input.read_key_blocking(timeout: timeout)
            end

            def enable_mouse
              @input.enable_mouse
            end

            def disable_mouse
              @input.disable_mouse
            end

            def read_input_with_mouse(timeout: nil)
              @input.read_input_with_mouse(timeout: timeout)
            end

            def setup_signal_handlers(&)
              @input.setup_signal_handlers(&)
            end

            attr_reader :buffer, :buffer_manager, :output, :input

            def reset!
              @output = TerminalOutput.new($stdout)
              @buffer_manager = TerminalBuffer.new(@output, runtime_config: @runtime_config)
              @input = TerminalInput.new
              @buffer = @buffer_manager.buffer
              @color_mode = nil
            end

            def configure_runtime_config(runtime_config)
              unless runtime_config.is_a?(Shoko::Application::Ports::Outbound::RuntimeConfig)
                raise ArgumentError, 'runtime_config must implement Application::Ports::Outbound::RuntimeConfig'
              end

              @runtime_config = runtime_config
            end

            def color_mode
              @color_mode ||= detect_color_mode
            end

            def refresh_color_mode
              @color_mode = detect_color_mode
            end

            private

            def detect_color_mode
              override = ENV['SHOKO_COLOR_MODE'].to_s.downcase
              return :light if override == 'light'
              return :dark if override == 'dark'

              colorfgbg = ENV.fetch('COLORFGBG', '')
              mode = mode_from_colorfgbg(colorfgbg)
              return mode if mode

              if osc_query_enabled?
                rgb = @input&.query_default_background
                return mode_from_rgb(rgb) if rgb
              end

              :dark
            end

            def osc_query_enabled?
              value = ENV.fetch('SHOKO_ENABLE_OSC_QUERY', '').to_s.strip.downcase
              %w[1 true yes on].include?(value)
            end

            def mode_from_colorfgbg(value)
              bg_value = value.to_s.split(';').last
              return nil if bg_value.nil? || bg_value.empty?

              bg = Integer(bg_value)

              return nil unless bg

              bg >= 7 ? :light : :dark
            end

            def mode_from_rgb(rgb)
              r, g, b = rgb
              luminance = (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
              luminance >= 0.6 ? :light : :dark
            end
          end
        end
      end
    end
  end
end
