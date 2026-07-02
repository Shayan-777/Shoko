# frozen_string_literal: true

require 'time'

module Shoko
  module Core
    module Models
      # Represents a bookmark within a document.
      #
      # +anchor+ is an optional serialized DocumentAnchor hash for the
      # bookmarked line, so a jump re-locates the same TEXT under the current
      # layout; the raw wrapped-line offset is the fallback for records that
      # predate anchors.
      Bookmark = Struct.new(:chapter_index, :line_offset, :text_snippet, :created_at, :anchor) do
        # Build from hash loaded from disk
        # @param hash [Hash]
        # @return [Bookmark]
        def self.from_h(hash)
          new(
            chapter_index: hash['chapter'],
            line_offset: hash['line_offset'],
            text_snippet: hash['text'],
            created_at: Time.parse(hash['timestamp']),
            anchor: hash['anchor']
          )
        end

        # Convert to hash for persistence
        # @return [Hash]
        def to_h
          {
            'chapter' => chapter_index,
            'line_offset' => line_offset,
            'text' => text_snippet,
            'timestamp' => created_at.iso8601,
            'anchor' => anchor,
          }
        end
      end
    end
  end
end
