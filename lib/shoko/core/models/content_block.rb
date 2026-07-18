# frozen_string_literal: true

require_relative '../../shared/hash_normalizer'

module Shoko
  module Core
    module Models
      # Represents a unit of formatted content (heading, paragraph, list item, etc.).
      ContentBlock = Struct.new(:type, :segments, :level, :metadata) do
        def initialize(type:, segments:, level: 0, metadata: nil)
          super(
            type: type,
            segments: segments || [],
            level: level,
            metadata: Shoko::Shared::HashNormalizer.deep_symbolize(metadata) || {}
          )
        end

        def text
          segments.to_a.map { |segment| segment&.text.to_s }.join
        end

        def heading_level
          (metadata && metadata[:level]) || level
        end
      end
    end
  end
end
