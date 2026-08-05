# frozen_string_literal: true

require_relative 'value_normalizer'

module Shoko
  module Core
    module Models
      # Represents a bookmark within a document.
      #
      # +anchor+ is an optional DocumentAnchor-compatible value for the
      # bookmarked line, so a jump re-locates the same TEXT under the current
      # layout; the raw wrapped-line offset is the fallback for records that
      # predate anchors.
      Bookmark = Data.define(:chapter_index, :line_offset, :text_snippet, :created_at, :anchor) do
        def initialize(chapter_index:, line_offset:, text_snippet:, created_at:, anchor: nil)
          super(
            chapter_index: Integer(chapter_index),
            line_offset: Integer(line_offset),
            text_snippet: ValueNormalizer.immutable(text_snippet.to_s),
            created_at: created_at,
            anchor: ValueNormalizer.immutable(anchor)
          )
        end
      end
    end
  end
end
