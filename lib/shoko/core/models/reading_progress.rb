# frozen_string_literal: true

require_relative 'value_normalizer'

module Shoko
  module Core
    module Models
      # Immutable reading progress payload used across adapters and application services.
      #
      # +anchor+ is an optional DocumentAnchor-compatible value for the saved
      # position's top visible line. It re-locates the position under the
      # CURRENT layout at restore time; the raw wrapped-line offset remains
      # the fallback for records that predate anchors (or whose anchor no
      # longer resolves).
      ReadingProgress = Data.define(:chapter_index, :line_offset, :timestamp, :anchor) do
        def initialize(chapter_index:, line_offset:, timestamp:, anchor: nil)
          super(
            chapter_index: Integer(chapter_index),
            line_offset: Integer(line_offset),
            timestamp: ValueNormalizer.immutable(timestamp.to_s),
            anchor: ValueNormalizer.immutable(anchor)
          )
        end
      end
    end
  end
end
