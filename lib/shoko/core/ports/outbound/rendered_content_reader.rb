# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Port interface for reading rendered content state.
        # Adapters implementing this interface provide access to rendered lines
        # without coupling core services to application state selectors.
        #
        # @example Implementing this port
        #   class RenderedContentReaderAdapter
        #     include Shoko::Core::Ports::Outbound::RenderedContentReader
        #
        #     def initialize(render_registry:)
        #       @render_registry = render_registry
        #     end
        #
        #     def rendered_lines
        #       @render_registry.lines
        #     end
        #   end
        module RenderedContentReader
          # Get the currently rendered lines
          #
          # @return [Array] Array of rendered line data
          def rendered_lines
            raise NotImplementedError, "#{self.class} must implement #rendered_lines"
          end
        end
      end
    end
  end
end
