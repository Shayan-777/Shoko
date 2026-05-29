# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Capability port for reader overlay and sidebar surfaces whose state
        # is owned by long-lived UI components and cannot yet be inverted into
        # plain state observation. Methods that only wrote application state
        # have moved to ReaderViewMutator (handled by Part B.1).
        module ReaderOverlayControl
          def show_toc_sidebar
            raise NotImplementedError, "#{self.class} must implement #show_toc_sidebar"
          end

          def show_bookmarks_sidebar
            raise NotImplementedError, "#{self.class} must implement #show_bookmarks_sidebar"
          end

          def show_annotations_sidebar
            raise NotImplementedError, "#{self.class} must implement #show_annotations_sidebar"
          end

          def show_annotations_overlay
            raise NotImplementedError, "#{self.class} must implement #show_annotations_overlay"
          end

          def toggle_sidebar_visibility
            raise NotImplementedError, "#{self.class} must implement #toggle_sidebar_visibility"
          end

          def move_sidebar_selection(delta:)
            raise NotImplementedError, "#{self.class} must implement #move_sidebar_selection"
          end

          def activate_sidebar_selection
            raise NotImplementedError, "#{self.class} must implement #activate_sidebar_selection"
          end
        end
      end
    end
  end
end
