# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Sidebar
          # Shared TOC helper methods mixed into SidebarController.
          module TocFacade
            def toc_entries_for(doc)
              @toc_navigation.entries_for(doc)
            end

            def toc_collapsed_for(entries, raw = nil)
              raw = @sidebar_state.sidebar_toc_collapsed if raw.nil?
              @toc_navigation.collapsed_for(entries, raw)
            end

            def toc_visible_indices(entries, collapsed)
              @toc_navigation.visible_indices(
                entries,
                collapsed,
                filter_text: toc_filter_text,
                filter_active: toc_filter_active?
              )
            end

            def toc_entry_has_children?(entries, index)
              @toc_navigation.entry_has_children?(entries, index)
            end

            private

            def toggle_toc_collapsed(collapsed, index)
              @toc_navigation.toggle_collapsed(collapsed, index)
            end

            def ensure_visible_toc_selection(entries, collapsed, current)
              @toc_navigation.ensure_visible_selection(
                entries,
                collapsed,
                current,
                filter_text: toc_filter_text,
                filter_active: toc_filter_active?
              )
            end

            def navigable_toc_entry_indices(entries, collapsed)
              @toc_navigation.navigable_indices(
                entries,
                collapsed,
                filter_text: toc_filter_text,
                filter_active: toc_filter_active?
              )
            end

            def toc_filter_active?
              @sidebar_state.sidebar_toc_filter_active?
            rescue Shoko::Error
              false
            end

            def toc_filter_text
              return '' unless toc_filter_active?

              @sidebar_state.sidebar_toc_filter.to_s
            rescue Shoko::Error
              ''
            end
          end
        end
      end
    end
  end
end
