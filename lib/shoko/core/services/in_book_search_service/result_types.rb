# frozen_string_literal: true

module Shoko
  module Core
    module Services
      class InBookSearchService
        # Single search hit with chapter location and context around the match.
        # +line_index+ is the chapter-absolute line (used for navigation);
        # +page_line_index+ is its 0-based position within its page (for display,
        # nil when not paginated).
        SearchMatch = Struct.new(
          :chapter_index,
          :chapter_title,
          :line_index,
          :before,
          :match,
          :after,
          :line_space,
          :page_index,
          :page_line_index
        )

        # Search output payload.
        SearchResult = Struct.new(:query, :matches, :total_matches)
        SearchableLine = Struct.new(
          :chapter_index, :chapter_title, :line_index, :text, :line_space, :page_index, :page_line_index
        )
      end
    end
  end
end
