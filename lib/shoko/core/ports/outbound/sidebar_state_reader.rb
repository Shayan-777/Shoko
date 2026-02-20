# frozen_string_literal: true

module Shoko
  module Core
    module Ports::Outbound
      # Application-facing contract for sidebar state reads.
      module SidebarStateReader
        def sidebar_visible?
          raise NotImplementedError, "#{self.class} must implement #sidebar_visible?"
        end

        def sidebar_active_tab
          raise NotImplementedError, "#{self.class} must implement #sidebar_active_tab"
        end

        def sidebar_toc_selected
          raise NotImplementedError, "#{self.class} must implement #sidebar_toc_selected"
        end

        def sidebar_toc_collapsed
          raise NotImplementedError, "#{self.class} must implement #sidebar_toc_collapsed"
        end

        def sidebar_bookmarks_selected
          raise NotImplementedError, "#{self.class} must implement #sidebar_bookmarks_selected"
        end

        def sidebar_annotations_selected
          raise NotImplementedError, "#{self.class} must implement #sidebar_annotations_selected"
        end

        def sidebar_prev_view_mode
          raise NotImplementedError, "#{self.class} must implement #sidebar_prev_view_mode"
        end

        def sidebar_toc_filter
          raise NotImplementedError, "#{self.class} must implement #sidebar_toc_filter"
        end

        def sidebar_toc_filter_active?
          raise NotImplementedError, "#{self.class} must implement #sidebar_toc_filter_active?"
        end
      end
    end
  end
end
