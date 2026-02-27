# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Runtime boundary for redraw and scan operations in menu workflows.
        module MenuWorkflowRuntime
          def draw_screen
            raise NotImplementedError, "#{self.class} must implement #draw_screen"
          end

          def refresh_scan(force:)
            raise NotImplementedError, "#{self.class} must implement #refresh_scan"
          end
        end
      end
    end
  end
end
