# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Capability port for reader overlay surfaces whose state is owned by
        # long-lived UI components and cannot yet be inverted into plain state
        # observation.
        module ReaderOverlayControl
          def show_annotations_overlay
            raise NotImplementedError, "#{self.class} must implement #show_annotations_overlay"
          end
        end
      end
    end
  end
end
