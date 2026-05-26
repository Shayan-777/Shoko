# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Capability port for triggering a catalog refresh after workflow side effects.
        module CatalogRefreshControl
          def refresh_catalog(force:)
            raise NotImplementedError, "#{self.class} must implement #refresh_catalog"
          end
        end
      end
    end
  end
end
