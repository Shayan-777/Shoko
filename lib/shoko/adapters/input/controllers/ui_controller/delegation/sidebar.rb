# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module UiControllerDelegation
          # Delegates sidebar tab, selection, and visibility commands to the sidebar controller.
          module Sidebar
            def open_toc
              @sidebar_controller.open_toc
            end

            def open_bookmarks
              @sidebar_controller.open_bookmarks
            end

            def open_annotations_tab
              @sidebar_controller.open_annotations_tab
            end

            def activate_sidebar_tab(tab)
              @sidebar_controller.activate_sidebar_tab(tab)
            end

            def handle_sidebar_toc_click(index)
              @sidebar_controller.handle_sidebar_toc_click(index)
            end

            def select_sidebar_toc_index(index)
              @sidebar_controller.select_sidebar_toc_index(index)
            end

            def sidebar_down
              @sidebar_controller.sidebar_down
            end

            def sidebar_up
              @sidebar_controller.sidebar_up
            end

            def sidebar_select
              @sidebar_controller.sidebar_select
            end

            def sidebar_toggle_toc
              @sidebar_controller.sidebar_toggle_toc
            end

            def sidebar_visible?
              @sidebar_controller.sidebar_visible?
            end

            def close_sidebar_with_restore(tab)
              @sidebar_controller.close_sidebar_with_restore(tab)
            end

            def toc_entries_for(doc)
              @sidebar_controller.toc_entries_for(doc)
            end

            def toc_collapsed_for(entries, raw = nil)
              @sidebar_controller.toc_collapsed_for(entries, raw)
            end

            def toc_visible_indices(entries, collapsed)
              @sidebar_controller.toc_visible_indices(entries, collapsed)
            end

            def toc_entry_has_children?(entries, index)
              @sidebar_controller.toc_entry_has_children?(entries, index)
            end
          end
        end
      end
    end
  end
end
