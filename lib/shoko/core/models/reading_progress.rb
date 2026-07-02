# frozen_string_literal: true

require_relative '../../shared/hash_normalizer'

module Shoko
  module Core
    module Models
      # Immutable reading progress payload used across adapters and application services.
      #
      # +anchor+ is an optional serialized DocumentAnchor hash for the saved
      # position's top visible line. It re-locates the position under the
      # CURRENT layout at restore time; the raw wrapped-line offset remains
      # the fallback for records that predate anchors (or whose anchor no
      # longer resolves).
      ReadingProgress = Data.define(:chapter_index, :line_offset, :timestamp, :anchor) do
        def initialize(chapter_index:, line_offset:, timestamp:, anchor: nil)
          super
        end

        def to_h
          {
            chapter: chapter_index,
            line_offset: line_offset,
            timestamp: timestamp,
            anchor: anchor,
          }
        end

        class << self
          def from_h(hash)
            return nil unless hash

            normalized = Shoko::Shared::HashNormalizer.symbolize_keys(hash) || {}
            new(
              chapter_index: normalized[:chapter],
              line_offset: normalized[:line_offset],
              timestamp: normalized[:timestamp],
              anchor: normalized[:anchor]
            )
          end
        end
      end
    end
  end
end
