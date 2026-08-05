# frozen_string_literal: true

require 'time'
require 'shoko/core/models/bookmark'

module Shoko
  module Adapters
    module Storage
      module Codecs
        # Owns the stable bookmarks.json record shape.
        module BookmarkCodec
          module_function

          def load(payload)
            Core::Models::Bookmark.new(
              chapter_index: payload.fetch('chapter'),
              line_offset: payload.fetch('line_offset'),
              text_snippet: payload['text'],
              created_at: Time.iso8601(payload.fetch('timestamp')),
              anchor: payload['anchor']
            )
          end

          def dump(bookmark)
            {
              'chapter' => bookmark.chapter_index,
              'line_offset' => bookmark.line_offset,
              'text' => bookmark.text_snippet,
              'timestamp' => bookmark.created_at.iso8601,
              'anchor' => bookmark.anchor,
            }
          end
        end
      end
    end
  end
end
