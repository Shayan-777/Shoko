# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Boundary for constructing menu progress presenters.
        module MenuProgressPresenters
          def build
            raise NotImplementedError, "#{self.class} must implement #build"
          end
        end
      end
    end
  end
end
