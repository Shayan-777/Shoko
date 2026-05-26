# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port for collaborators that expose lazily hydrated wrapped pages.
        module DynamicPageSource
          def pages_data
            raise NotImplementedError, "#{self.class} must implement #pages_data"
          end

          def get_page(page_index, width: nil, height: nil, sidebar_visible: nil)
            raise NotImplementedError, "#{self.class} must implement #get_page"
          end
        end
      end
    end
  end
end
