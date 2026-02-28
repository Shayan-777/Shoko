# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Boundary for generating domain-safe identifiers.
        module IdGenerator
          def uuid
            raise NotImplementedError, "#{self.class} must implement #uuid"
          end
        end
      end
    end
  end
end
