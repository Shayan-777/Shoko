# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for render-related state updates.
      # Manages rendered lines metadata that overlays and mouse handlers need.
      #
      # This port separates render-time state mutations from the rendering
      # components themselves, allowing the coordinator to manage the lifecycle.
      module RenderStateWriter
        # Clear rendered lines at the start of a new frame.
        # Called by the render coordinator before rendering begins.
        #
        # @return [void]
        def clear_rendered_lines
          raise NotImplementedError, "#{self.class} must implement #clear_rendered_lines"
        end

        # Update rendered lines after rendering completes.
        # Stores geometry metadata for mouse interactions and overlays.
        #
        # @param rendered_lines [Hash] Line geometry data from the render pass
        # @return [void]
        def update_rendered_lines(rendered_lines)
          raise NotImplementedError, "#{self.class} must implement #update_rendered_lines"
        end
      end
    end
  end
end
