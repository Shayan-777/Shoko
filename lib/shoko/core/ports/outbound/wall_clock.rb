# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Boundary for reading current wall-clock time.
        module WallClock
          def utc_now
            raise NotImplementedError, "#{self.class} must implement #utc_now"
          end
        end
      end
    end
  end
end
