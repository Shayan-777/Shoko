# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Application-facing contract for pagination state mutations.
        module PaginationStateWriter
          def update_pagination_state(attrs)
            raise NotImplementedError, "#{self.class} must implement #update_pagination_state"
          end

          def update_page(attrs)
            raise NotImplementedError, "#{self.class} must implement #update_page"
          end

          def update_selections(attrs)
            raise NotImplementedError, "#{self.class} must implement #update_selections"
          end
        end
      end
    end
  end
end
