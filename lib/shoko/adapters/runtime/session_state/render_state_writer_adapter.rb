# frozen_string_literal: true

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-local collaborator for render-related state updates.
        class RenderStateWriterAdapter
          def initialize(_state = nil, render_registry: nil, logger: nil)
            @render_registry = render_registry
            @logger = logger
          end

          # Clear render metadata at the start of a new frame.
          # @return [void]
          def clear_rendered_lines
            @render_registry&.clear
          # resilient-boundary
          rescue Shoko::Error => e
            log_error('clear_rendered_lines', e)
            raise
          end

          # Update rendered lines after rendering completes.
          # @param rendered_lines [Hash] Line geometry data
          # @return [void]
          def update_rendered_lines(rendered_lines)
            @render_registry&.write(rendered_lines)
          # resilient-boundary
          rescue Shoko::Error => e
            log_error('update_rendered_lines', e)
            raise
          end

          private

          def log_error(operation, error)
            @logger&.error(
              "render_state_writer.#{operation}_failed",
              error: error.class.name,
              message: error.message,
              backtrace: error.backtrace&.first(5)&.join("\n")
            )
          end
        end
      end
    end
  end
end
