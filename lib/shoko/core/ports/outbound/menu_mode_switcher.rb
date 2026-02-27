# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Boundary for changing active menu/reader UI mode.
        module MenuModeSwitcher
          def switch_mode(mode)
            raise NotImplementedError, "#{self.class} must implement #switch_mode"
          end
        end
      end
    end
  end
end
