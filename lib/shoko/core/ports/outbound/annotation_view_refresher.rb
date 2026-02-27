# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Boundary for triggering annotation list refresh after mutation.
        module AnnotationViewRefresher
          def refresh_annotations_view
            raise NotImplementedError, "#{self.class} must implement #refresh_annotations_view"
          end
        end
      end
    end
  end
end
