# frozen_string_literal: true

module Shoko
  module Application
    module State
      module Schema
        # Application-owned reader pagination-state schema fragment.
        #
        # Pagination is an application/runtime concern: page maps, totals, and
        # layout-cache keys are derived by the application's pagination services
        # to satisfy the rendering pipeline. The reader's logical position
        # (current chapter/page) lives in `Core::Reading::Schema`; this fragment
        # owns the derived shape produced by computing pagination.
        module ReaderPagination
          PARTITION = :reader

          FIELDS = %i[
            page_map
            total_pages
            pages_per_chapter
            page_offset
            last_width
            last_height
            dynamic_page_map
            dynamic_total_pages
            dynamic_chapter_starts
            last_dynamic_width
            last_dynamic_height
          ].freeze

          DEFAULTS = {
            page_map: [],
            total_pages: 0,
            pages_per_chapter: [],
            page_offset: 0,
            last_width: 0,
            last_height: 0,
            dynamic_page_map: nil,
            dynamic_total_pages: 0,
            dynamic_chapter_starts: [],
            last_dynamic_width: 0,
            last_dynamic_height: 0,
          }.freeze

          module_function

          def contribute(_context = {})
            { PARTITION => DEFAULTS.dup }
          end
        end
      end
    end
  end
end
