# frozen_string_literal: true

require_relative 'base_action'
require_relative '../../../adapters/output/render_registry'

module Shoko
  module Application
    module Actions
      # Action for updating rendered lines cache
      class UpdateRenderedLinesAction < BaseAction
        def initialize(rendered_lines)
          super(rendered_lines: rendered_lines)
        end

        def apply(state)
          registry = begin
            state.resolve(:render_registry) if state.respond_to?(:resolve)
          rescue StandardError
            nil
          end
          registry ||= begin
            Shoko::Adapters::Output::RenderRegistry.current
          rescue StandardError
            nil
          end
          registry&.write(payload[:rendered_lines])
          # Keep state entry lightweight for observers; avoid storing the large hash
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
