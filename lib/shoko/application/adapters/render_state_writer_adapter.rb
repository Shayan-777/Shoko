# frozen_string_literal: true

require_relative '../../core/ports/render_state_writer'
require_relative '../state/actions/update_rendered_lines_action'

module Shoko
  module Application
    module Adapters
      # Application adapter implementing the RenderStateWriter port.
      # Manages render-related state updates with proper error logging.
      class RenderStateWriterAdapter
        include Core::Ports::RenderStateWriter

        def initialize(state, render_registry: nil, logger: nil)
          @state = state
          @render_registry = render_registry
          @logger = logger
        end

        # Clear rendered lines at the start of a new frame.
        # @return [void]
        def clear_rendered_lines
          @state.dispatch(Actions::ClearRenderedLinesAction.new)
        rescue StandardError => e
          log_error('clear_rendered_lines', e)
        end

        # Update rendered lines after rendering completes.
        # @param rendered_lines [Hash] Line geometry data
        # @return [void]
        def update_rendered_lines(rendered_lines)
          @render_registry&.write(rendered_lines)
          @state.dispatch(Actions::UpdateRenderedLinesAction.new(rendered_lines))
        rescue StandardError => e
          log_error('update_rendered_lines', e)
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
