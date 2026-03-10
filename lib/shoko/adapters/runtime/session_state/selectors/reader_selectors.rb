# frozen_string_literal: true

module Shoko
  module Adapters
    module Runtime
      module SessionState
        module Selectors
          # Selectors for reader state - provides read-only access to state
          # Replaces direct state access and convenience methods
          module ReaderSelectors
            module_function

            # Chapter and page selectors
            def current_chapter(state)
              state.get(%i[reader current_chapter])
            end

            def current_page_index(state)
              state.get(%i[reader current_page_index])
            end

            def left_page(state)
              state.get(%i[reader left_page])
            end

            def right_page(state)
              state.get(%i[reader right_page])
            end

            def single_page(state)
              state.get(%i[reader single_page])
            end

            def current_page(state)
              current_page_index(state) + 1
            end

            # Mode and UI state selectors
            def mode(state)
              state.get(%i[reader mode])
            end

            def selection(state)
              state.get(%i[reader selection])
            end

            def message(state)
              state.get(%i[reader message])
            end

            def running(state)
              state.get(%i[reader running])
            end

            def running?(state)
              running(state)
            end

            # List selectors
            def bookmarks(state)
              state.get(%i[reader bookmarks]) || []
            end

            def annotations(state)
              state.get(%i[reader annotations]) || []
            end

            # Pagination selectors
            def page_map(state)
              state.get(%i[reader page_map]) || []
            end

            def total_pages(state)
              state.get(%i[reader total_pages])
            end

            def pages_per_chapter(state)
              state.get(%i[reader pages_per_chapter]) || []
            end

            # Dynamic pagination selectors
            def dynamic_page_map(state)
              state.get(%i[reader dynamic_page_map])
            end

            def dynamic_total_pages(state)
              state.get(%i[reader dynamic_total_pages])
            end

            def dynamic_chapter_starts(state)
              state.get(%i[reader dynamic_chapter_starts]) || []
            end

            # Terminal sizing selectors
            def last_width(state)
              state.get(%i[reader last_width])
            end

            def last_height(state)
              state.get(%i[reader last_height])
            end

            def last_dynamic_width(state)
              state.get(%i[reader last_dynamic_width])
            end

            def last_dynamic_height(state)
              state.get(%i[reader last_dynamic_height])
            end

            def terminal_size_changed?(state, width, height)
              width != last_width(state) || height != last_height(state)
            end

            def search_landing_highlight(state)
              state.get(%i[reader search_landing_highlight])
            end

            # Sidebar selectors
            def sidebar_visible(state)
              state.get(%i[reader sidebar_visible])
            end

            def sidebar_visible?(state)
              sidebar_visible(state)
            end

            def sidebar_active_tab(state)
              state.get(%i[reader sidebar_active_tab])
            end

            def sidebar_toc_selected(state)
              state.get(%i[reader sidebar_toc_selected])
            end

            def sidebar_toc_collapsed(state)
              state.get(%i[reader sidebar_toc_collapsed])
            end

            def sidebar_annotations_selected(state)
              state.get(%i[reader sidebar_annotations_selected])
            end

            def sidebar_bookmarks_selected(state)
              state.get(%i[reader sidebar_bookmarks_selected])
            end

            def sidebar_toc_filter(state)
              state.get(%i[reader sidebar_toc_filter])
            end

            def sidebar_toc_filter_active(state)
              state.get(%i[reader sidebar_toc_filter_active])
            end

            def sidebar_toc_filter_active?(state)
              sidebar_toc_filter_active(state)
            end
          end
        end
      end
    end
  end
end
