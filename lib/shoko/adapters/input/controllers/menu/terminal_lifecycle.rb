# frozen_string_literal: true

require 'shoko/shared/resilient_diagnostics'
require 'shoko/shared/errors'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Owns menu terminal setup, mouse-tracking state, and restoration.
          # Cleanup remains idempotent and diagnostic failures never interfere
          # with restoration or process termination.
          class TerminalLifecycle
            def initialize(terminal:, process_control:, logger: nil, output: $stdout)
              @terminal = terminal
              @process_control = process_control
              @logger = logger
              @output = output
              @mouse_tracking = false
            end

            def setup
              @terminal.setup
            end

            def returned_from_reader!
              @mouse_tracking = false
            end

            def ensure_mouse_tracking
              return if @mouse_tracking

              @terminal.enable_mouse
              @mouse_tracking = true
            end

            def cleanup_and_exit(code, message, error = nil)
              cleanup
              emit_exit_message(message, error)
              log_exit(message, error)
              @process_control&.terminate(code)
            end

            def cleanup
              cleanup_error = nil
              begin
                disable_mouse
                @terminal.cleanup
              # resilient-boundary
              rescue StandardError => e
                cleanup_error = e
                record_cleanup_error(e)
              ensure
                force_cleanup_if_needed(cleanup_error)
              end
            end

            def ensure_cleanup
              @terminal.force_cleanup
            # resilient-boundary
            rescue StandardError => e
              record_ensure_cleanup_error(e)
            end

            def log_fatal_external_input(error)
              Shoko::Shared::ResilientDiagnostics.error(
                @logger,
                Shoko::FatalExternalInputError.event_id(error),
                error: error.class.name,
                message: error.message
              )
            end

            private

            def disable_mouse
              return unless @mouse_tracking

              @terminal.disable_mouse
              @mouse_tracking = false
            rescue Shoko::Error
              @mouse_tracking = false
            end

            def force_cleanup_if_needed(cleanup_error)
              remaining_depth = @terminal.session_depth || 0
              return unless cleanup_error || remaining_depth.positive?

              @terminal.force_cleanup
            # resilient-boundary
            rescue StandardError => e
              record_force_cleanup_error(e)
            end

            def emit_exit_message(message, error)
              return if message.to_s.empty?

              @output.puts(message)
              @output.puts('Run with --log PATH --log-level debug for details.') if error
            # resilient-boundary
            rescue StandardError => e
              record_exit_message_error(e)
            end

            def log_exit(message, error)
              Shoko::Shared::ResilientDiagnostics.info(
                @logger,
                'Exiting menu',
                message: message,
                status: error ? 'error' : 'ok'
              )
              return unless error

              Shoko::Shared::ResilientDiagnostics.error(
                @logger,
                'Menu exit error',
                error: error.message,
                backtrace: Array(error.backtrace)
              )
            end

            def record_cleanup_error(error)
              diagnostic_error('Menu terminal cleanup failed', error)
            end

            def record_force_cleanup_error(error)
              diagnostic_error('Menu terminal force cleanup failed', error)
            end

            def record_ensure_cleanup_error(error)
              diagnostic_error('menu.run.ensure_terminal_cleanup_failed', error)
            end

            def record_exit_message_error(error)
              diagnostic_error('menu.exit_message_failed', error)
            end

            def diagnostic_error(event, error)
              Shoko::Shared::ResilientDiagnostics.error(
                @logger,
                event,
                error_class: error.class.name,
                error: error.message
              )
              nil
            end
          end
        end
      end
    end
  end
end
