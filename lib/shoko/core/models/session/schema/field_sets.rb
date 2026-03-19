# frozen_string_literal: true

module Shoko
  module Core
    module Models
      module Session
        # Canonical reader session field lists.
        module Schema
          READER_SESSION_FIELDS = %i[
            current_chapter
            left_page
            right_page
            single_page
            current_page
            current_page_index
            mode
            selection
            message
            running
            bookmarks
            annotations
            total_chapters
            pending_progress
            pending_jump
            book_path
          ].freeze

          READER_PAGINATION_FIELDS = %i[
            page_map
            total_pages
            pages_per_chapter
            last_width
            last_height
            page_offset
            dynamic_page_map
            dynamic_total_pages
            dynamic_chapter_starts
            last_dynamic_width
            last_dynamic_height
          ].freeze

          READER_VIEW_STATE_FIELDS = %i[
            search_landing_highlight
            hovered_inline_link
            dictionary_visible
            sidebar_visible
            sidebar_active_tab
            sidebar_prev_view_mode
            sidebar_toc_selected
            sidebar_annotations_selected
            sidebar_bookmarks_selected
            sidebar_toc_filter
            sidebar_toc_filter_active
            sidebar_toc_collapsed
            loading_active
            loading_message
            loading_progress
          ].freeze

          READER_FIELDS = %i[
            current_chapter
            left_page
            right_page
            single_page
            current_page
            current_page_index
            mode
            selection
            message
            running
            bookmarks
            annotations
            page_map
            total_pages
            total_chapters
            pages_per_chapter
            last_width
            last_height
            page_offset
            dynamic_page_map
            dynamic_total_pages
            dynamic_chapter_starts
            last_dynamic_width
            last_dynamic_height
            search_landing_highlight
            hovered_inline_link
            dictionary_visible
            sidebar_visible
            sidebar_active_tab
            sidebar_prev_view_mode
            sidebar_toc_selected
            sidebar_annotations_selected
            sidebar_bookmarks_selected
            sidebar_toc_filter
            sidebar_toc_filter_active
            sidebar_toc_collapsed
            pending_progress
            pending_jump
            book_path
            loading_active
            loading_message
            loading_progress
          ].freeze
        end
      end
    end
  end
end
