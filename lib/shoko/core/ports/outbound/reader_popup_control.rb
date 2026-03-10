# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Capability port for reader popup selection flows.
        module ReaderPopupControl
          def move_popup_selection(delta:)
            raise NotImplementedError, "#{self.class} must implement #move_popup_selection"
          end

          def confirm_popup
            raise NotImplementedError, "#{self.class} must implement #confirm_popup"
          end

          def cancel_popup
            raise NotImplementedError, "#{self.class} must implement #cancel_popup"
          end
        end
      end
    end
  end
end
