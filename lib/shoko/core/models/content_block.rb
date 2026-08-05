# frozen_string_literal: true

require_relative '../../shared/hash_normalizer'
require_relative 'value_normalizer'

module Shoko
  module Core
    module Models
      # Represents a unit of formatted content (heading, paragraph, list item, etc.).
      ContentBlock = Data.define(:type, :segments, :level, :metadata) do
        def initialize(type:, segments:, level: 0, metadata: nil)
          super(
            type: type,
            segments: ValueNormalizer.immutable(Array(segments)),
            level: Integer(level),
            metadata: normalized_metadata(metadata)
          )
        end

        def text
          segments.to_a.map { |segment| segment&.text.to_s }.join
        end

        def heading_level
          (metadata && metadata[:level]) || level
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
