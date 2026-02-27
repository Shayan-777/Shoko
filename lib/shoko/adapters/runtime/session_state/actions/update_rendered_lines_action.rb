# frozen_string_literal: true

require_relative 'base_action'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        module Actions
          # Action for updating rendered lines cache
          class UpdateRenderedLinesAction < BaseAction
            def initialize(rendered_lines)
              super(rendered_lines: rendered_lines)
            end

            def apply(state)
              # Keep state entry lightweight for observers; avoid storing the large hash.
              # The actual rendered lines data is written to the RenderRegistry by the
              # caller (RenderStateWriterAdapter) before dispatching this action.
              state.update({ %i[reader rendered_lines] => :render_registry })
            end
          end

          # Convenience action for clearing rendered lines
          class ClearRenderedLinesAction < UpdateRenderedLinesAction
            def initialize
              super({})
            end
          end
        end
      end
    end
  end
end
