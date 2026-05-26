# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Capability port for menu browse/library selection inspection.
        module MenuBrowseInspection
          def browse_item_count
            raise NotImplementedError, "#{self.class} must implement #browse_item_count"
          end

          def library_item_count
            raise NotImplementedError, "#{self.class} must implement #library_item_count"
          end

          def selected_library_path
            raise NotImplementedError, "#{self.class} must implement #selected_library_path"
          end
        end
      end
    end
  end
end
