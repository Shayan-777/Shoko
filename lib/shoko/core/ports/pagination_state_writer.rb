# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Focused writer for pagination/loading state updates.
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

        def update_ui_loading(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_ui_loading"
        end
      end
    end
  end
end
