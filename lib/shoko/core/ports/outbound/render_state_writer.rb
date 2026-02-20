# frozen_string_literal: true

module Shoko
  module Core
    module Ports::Outbound
      # Port interface for render-related state updates.
      module RenderStateWriter
        # Clear rendered lines at the start of a new frame.
        def clear_rendered_lines
          raise NotImplementedError, "#{self.class} must implement #clear_rendered_lines"
        end

        # Update rendered lines after rendering completes.
        def update_rendered_lines(rendered_lines)
          raise NotImplementedError, "#{self.class} must implement #update_rendered_lines"
        end
      end
    end
  end
end
