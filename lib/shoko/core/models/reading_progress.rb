# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Immutable reading progress payload used across adapters and application services.
      class ReadingProgress < Data.define(:chapter_index, :line_offset, :timestamp)
        def to_h
          {
            chapter: chapter_index,
            line_offset: line_offset,
            timestamp: timestamp,
          }
        end

        class << self
          def from_h(hash)
            return nil unless hash

            new(
              chapter_index: hash['chapter'] || hash[:chapter],
              line_offset: hash['line_offset'] || hash[:line_offset],
              timestamp: hash['timestamp'] || hash[:timestamp]
            )
          end
        end
      end
    end
  end
end
