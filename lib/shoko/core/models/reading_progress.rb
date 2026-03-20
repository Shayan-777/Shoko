# frozen_string_literal: true

require_relative '../../shared/hash_normalizer'

module Shoko
  module Core
    module Models
      # Immutable reading progress payload used across adapters and application services.
      ReadingProgress = Data.define(:chapter_index, :line_offset, :timestamp) do
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

            normalized = Shoko::Shared::HashNormalizer.symbolize_keys(hash) || {}
            new(
              chapter_index: normalized[:chapter],
              line_offset: normalized[:line_offset],
              timestamp: normalized[:timestamp]
            )
          end
        end
      end
    end
  end
end
