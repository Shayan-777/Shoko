# frozen_string_literal: true

require_relative '../../../core/ports/outbound/rendered_content_reader'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Application adapter implementing the RenderedContentReader port.
        # Reads rendered content from the adapter-owned render registry.
        class RenderedContentReaderAdapter
          include Core::Ports::Outbound::RenderedContentReader

          def initialize(_state = nil, render_registry: nil)
            @render_registry = render_registry
          end

          # Get the currently rendered lines
          # @return [Hash] Rendered lines data
          def rendered_lines
            lines = @render_registry&.lines
            lines.is_a?(Hash) ? lines : {}
          end
        end
      end
    end
  end
end
