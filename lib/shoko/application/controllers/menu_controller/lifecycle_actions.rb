# frozen_string_literal: true

module Shoko
  module Application
    module Controllers
      module MenuControllerLifecycleActions
        def run
          @terminal_service.setup
          @catalog.load_cached
          epubs = @catalog.entries || []
          @filtered_epubs = epubs
          @main_menu_component.browse_screen.filtered_epubs = epubs
          @catalog.start_scan if epubs.empty?

          main_loop
        rescue Interrupt
          cleanup_and_exit(0, "\nGoodbye!")
        rescue StandardError => e
          cleanup_and_exit(1, "Error: #{e.message}", e)
        ensure
          begin
            if @terminal_service.respond_to?(:force_cleanup)
              @terminal_service.force_cleanup
            elsif @terminal_service.respond_to?(:cleanup)
              @terminal_service.cleanup
            end
          rescue StandardError
            # best effort; leave terminal as-is if cleanup fails here
          end
          @catalog.cleanup if @catalog.respond_to?(:cleanup)
        end

        def cleanup_and_exit(code, message, error = nil)
          cleanup_terminal

          log_exit(message, error)
          @process_control&.terminate(code)
        end

        def main_loop
          draw_screen
          loop do
            process_scan_results_if_available
            handle_user_input
            draw_screen
          end
        end

        def handle_user_input
          keys = read_input_keys(timeout: annotation_editor_active? ? blink_poll_interval : nil)
          input_controller.handle_keys(keys)
        end

        def read_input_keys(timeout: nil)
          @terminal_service.read_keys_blocking(limit: 10, timeout: timeout)
        end

        def process_scan_results_if_available
          return unless (epubs = @catalog.process_results)

          @filtered_epubs = epubs
          @main_menu_component.browse_screen.filtered_epubs = epubs
          @main_menu_component.library_screen.invalidate_cache!
        end

        def draw_screen
          notification_service&.tick
          @frame_coordinator.with_frame do |surface, bounds, _w, _h|
            @render_pipeline.render_component(surface, bounds, @main_menu_component)
          end
        end

        def annotation_editor_active?
          @menu_state_reader.mode == :annotation_editor
        rescue StandardError
          false
        end

        def blink_poll_interval
          0.1
        end

        private

        def cleanup_terminal
          terminal = terminal_service
          return unless terminal

          cleanup_error = nil
          begin
            terminal.cleanup
          rescue StandardError => e
            cleanup_error = e
            @logger_ref&.error('Menu terminal cleanup failed', error: e.message)
          ensure
            force_cleanup_if_needed(terminal, cleanup_error)
          end
        end

        def force_cleanup_if_needed(terminal, cleanup_error)
          return unless terminal.respond_to?(:force_cleanup)

          remaining_depth = terminal.session_depth || 0
          needs_force = cleanup_error || remaining_depth.positive?
          return unless needs_force

          terminal.force_cleanup
        rescue StandardError => e
          @logger_ref&.error('Menu terminal force cleanup failed', error: e.message)
        end

        def log_exit(message, error)
          @logger_ref&.info('Exiting menu', message: message, status: error ? 'error' : 'ok')
          return unless error

          @logger_ref&.error('Menu exit error', error: error.message, backtrace: Array(error.backtrace))
        end
      end
    end
  end
end
