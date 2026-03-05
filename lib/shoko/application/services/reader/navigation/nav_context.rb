# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Reader
        module Navigation
          # Immutable snapshot of navigation-relevant state.
          NavContext = Struct.new(
            :mode,                 # :dynamic or :absolute
            :view_mode,            # :single or :split
            :current_chapter,      # Integer
            :total_chapters,       # Integer
            :current_page_index,   # Integer (dynamic)
            :dynamic_total_pages,  # Integer (dynamic total pages)
            :single_page,          # Integer (absolute single)
            :left_page,            # Integer (absolute split left)
            :right_page,           # Integer (absolute split right)
            :max_page_in_chapter,  # Integer (absolute page count)
            :lines_per_page,       # Integer (absolute single stride)
            :column_lines_per_page, # Integer (absolute split stride)
            :max_offset_in_chapter
          )
        end
      end
    end
  end
end
