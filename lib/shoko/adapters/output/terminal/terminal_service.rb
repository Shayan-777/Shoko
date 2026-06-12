# frozen_string_literal: true

require_relative '../../base_adapter'
require_relative '../../../application/ports/outbound/runtime_config'

module Shoko
  module Adapters
    module Output
      module Terminal
        # Terminal interaction service for mouse and rendering coordination
        class TerminalService < Shoko::Adapters::BaseAdapter
          # Session depth tracks nested setup/cleanup calls
          # (e.g., menu -> reader) to avoid flicker or dropping to shell.
          attr_accessor :session_depth

          def initialize(runtime_config:, logger: nil)
            super(logger: logger)
            unless runtime_config.is_a?(Shoko::Application::Ports::Outbound::RuntimeConfig)
              raise ArgumentError, 'runtime_config must implement Application::Ports::Outbound::RuntimeConfig'
            end

            @runtime_config = runtime_config
            @session_depth = 0
            @active = false
          end

          def enable_mouse
            Terminal.enable_mouse
          end

          def disable_mouse
            Terminal.disable_mouse
          end

          def read_input_with_mouse(timeout: nil)
            Terminal.read_input_with_mouse(timeout: timeout)
          end

          def read_key
            Terminal.read_key
          end

          def size
            Terminal.size
          end

          def end_frame
            Terminal.end_frame
          end

          def setup
            previous_depth = @session_depth || 0
            depth = previous_depth + 1
            @session_depth = depth
            logger&.debug('terminal.setup', depth: depth)
            return if previous_depth.positive?

            Terminal.setup
            @active = true
          rescue Shoko::Error => e
            @session_depth = previous_depth
            @active = false if previous_depth.zero?
            logger&.error('terminal.setup_failed', error: e.message)
            raise
          end

          def cleanup(force: false)
            return force_cleanup! if force

            depth_before = @session_depth || 0
            depth = decrement_session_depth
            logger&.debug('terminal.cleanup', depth: depth)
            return if depth_before.zero? || depth.positive?

            perform_terminal_cleanup
            @active = false
          rescue Shoko::Error => e
            logger&.error('terminal.cleanup_failed', error: e.message)
            raise
          end

          # Ensure session depth is at least the expected value (for nested sessions)
          # This guards against depth getting out of sync
          def ensure_session_depth(minimum_depth)
            current = @session_depth || 0
            return if current >= minimum_depth

            logger&.warn('terminal.depth_correction', current: current, expected: minimum_depth)
            @session_depth = minimum_depth
          end

          def force_cleanup
            cleanup(force: true)
          end

          def start_frame(width: nil, height: nil)
            Terminal.start_frame(width: width, height: height, runtime_config: @runtime_config)
          end

          def read_key_blocking(timeout: nil)
            Terminal.read_key_blocking(timeout: timeout)
          end

          # True once per terminal-resize burst; consuming refreshes the size
          # cache so the next frame is laid out against the new dimensions.
          def consume_resize_event?
            Terminal.consume_resize_event?
          end

          # Read one blocking key, then drain a few non-blocking extras.
          # Returns an array of keys, or [] if nothing was read.
          #
          # @param limit [Integer] maximum total keys to return
          # @return [Array<String>]
          def read_keys_blocking(limit: 10, timeout: nil)
            first = read_key_blocking(timeout: timeout)
            return [] unless first

            keys = [first]
            while (extra = read_key)
              keys << extra
              break if keys.size >= limit
            end
            keys
          end

          # Create a surface for component rendering
          def output
            Terminal
          end

          private

          def force_cleanup!
            depth = @session_depth || 0
            return unless @active || depth.positive?

            logger&.warn('terminal.cleanup.force', depth: depth)
            @session_depth = 0
            perform_terminal_cleanup
            @active = false
          end

          def decrement_session_depth
            depth = @session_depth
            return 0 unless depth

            new_depth = depth.positive? ? depth - 1 : 0
            @session_depth = new_depth
            new_depth
          end

          def perform_terminal_cleanup
            Terminal.cleanup
          end
        end
      end
    end
  end
end
