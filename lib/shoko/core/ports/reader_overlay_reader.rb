# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Focused reader for reader overlays and transient UI state.
      module ReaderOverlayReader
        def mode
          raise NotImplementedError, "#{self.class} must implement #mode"
        end

        def selection
          raise NotImplementedError, "#{self.class} must implement #selection"
        end

        def popup_menu
          raise NotImplementedError, "#{self.class} must implement #popup_menu"
        end

        def in_book_search_popup
          raise NotImplementedError, "#{self.class} must implement #in_book_search_popup"
        end

        def annotations_overlay
          raise NotImplementedError, "#{self.class} must implement #annotations_overlay"
        end

        def annotation_editor_overlay
          raise NotImplementedError, "#{self.class} must implement #annotation_editor_overlay"
        end

        def dictionary_popup
          raise NotImplementedError, "#{self.class} must implement #dictionary_popup"
        end

        def dictionary_panel
          raise NotImplementedError, "#{self.class} must implement #dictionary_panel"
        end

        def running?
          raise NotImplementedError, "#{self.class} must implement #running?"
        end

        def sidebar_visible?
          raise NotImplementedError, "#{self.class} must implement #sidebar_visible?"
        end

        def sidebar_active_tab
          raise NotImplementedError, "#{self.class} must implement #sidebar_active_tab"
        end
      end
    end
  end
end
