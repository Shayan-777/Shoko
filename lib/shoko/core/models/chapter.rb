# frozen_string_literal: true

require_relative '../../shared/hash_normalizer'
require_relative 'value_normalizer'

module Shoko
  module Core
    module Models
      # Represents a chapter within an EPUB document.
      Chapter = Data.define(:number, :title, :lines, :metadata, :blocks, :raw_content) do
        def initialize(number:, title:, lines:, metadata: nil, blocks: nil, raw_content: nil)
          super(
            number: number,
            title: ValueNormalizer.immutable(title.to_s),
            lines: ValueNormalizer.immutable(Array(lines)),
            metadata: normalized_metadata(metadata),
            blocks: blocks.nil? ? nil : ValueNormalizer.immutable(Array(blocks)),
            raw_content: raw_content && ValueNormalizer.immutable(raw_content.to_s)
          )
        end

        # Number of lines in the chapter
        # @return [Integer]
        def line_count
          lines.size
        end

        # Estimated reading time in minutes
        # @param wpm [Integer] words per minute
        # @return [Integer]
        def estimated_reading_time(wpm = 250)
          word_count = lines.join(' ').split.size
          (word_count / wpm.to_f).ceil
        end

        private

        def normalized_metadata(metadata)
          normalized = Shoko::Shared::HashNormalizer.deep_symbolize(metadata) || {}
          ValueNormalizer.immutable(normalized)
        end
      end
    end
  end
end
