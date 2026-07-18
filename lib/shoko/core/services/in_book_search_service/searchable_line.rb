# frozen_string_literal: true

module Shoko
  module Core
    module Services
      class InBookSearchService
        # One searchable plain line of a chapter, addressed by chapter and
        # parsed-line index.
        SearchableLine = Struct.new(:chapter_index, :chapter_title, :line_index, :text)
      end
    end
  end
end
