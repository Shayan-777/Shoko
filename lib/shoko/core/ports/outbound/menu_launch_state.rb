# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Runtime launch-state contract for menu bootstrap/workflow handoff.
        module MenuLaunchState
          def last_opened_path
            raise NotImplementedError, "#{self.class} must implement #last_opened_path"
          end

          def set_last_opened_path(_path)
            raise NotImplementedError, "#{self.class} must implement #set_last_opened_path"
          end

          def clear_last_opened_path
            raise NotImplementedError, "#{self.class} must implement #clear_last_opened_path"
          end
        end
      end
    end
  end
end
