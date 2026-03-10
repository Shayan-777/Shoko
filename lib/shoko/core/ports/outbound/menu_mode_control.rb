# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Capability port for activating menu UI modes.
        module MenuModeControl
          def activate_menu_mode(mode)
            raise NotImplementedError, "#{self.class} must implement #activate_menu_mode"
          end
        end
      end
    end
  end
end
