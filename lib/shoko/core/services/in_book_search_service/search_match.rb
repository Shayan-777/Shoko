# frozen_string_literal: true

module Shoko
  module Core
    module Services
      class InBookSearchService
        # Single search hit with chapter location and context around the match.
        # +line_index+ is the chapter's PLAIN parsed-line index (paragraph
        # position); the result navigator re-locates the hit in the current
        # wrapped layout by its before/match/after context.
        SearchMatch = Struct.new(
          :chapter_index,
          :chapter_title,
          :line_index,
          :before,
          :match,
          :after
        )
      end
    end
  end
end
