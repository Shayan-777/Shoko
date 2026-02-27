# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Port for monotonic clock access.
        module Clock
          def monotonic_now
            raise NotImplementedError, "#{self.class} must implement #monotonic_now"
          end
        end
      end
    end
  end
end
