# frozen_string_literal: true

module Shoko
  module Core
    module Services
      class InBookSearchService
        # Single search hit with chapter location and context around the match.
        SearchMatch = Struct.new(
          :chapter_index,
          :chapter_title,
          :line_index,
          :before,
          :match,
          :after,
          :line_space,
          :page_index
        )

        # Search output payload.
        SearchResult = Struct.new(:query, :matches, :total_matches)
        SearchableLine = Struct.new(:chapter_index, :chapter_title, :line_index, :text, :line_space, :page_index)
      end
    end
  end
end
