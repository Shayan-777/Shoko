# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Capability port for reader maintenance and return-to-menu lifecycle actions.
        module ReaderLifecycleControl
          def rebuild_pagination
            raise NotImplementedError, "#{self.class} must implement #rebuild_pagination"
          end

          def clear_pagination_cache
            raise NotImplementedError, "#{self.class} must implement #clear_pagination_cache"
          end

          def return_to_menu
            raise NotImplementedError, "#{self.class} must implement #return_to_menu"
          end
        end
      end
    end
  end
end
