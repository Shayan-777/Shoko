# frozen_string_literal: true

require_relative '../../shared/hash_normalizer'
require_relative 'value_normalizer'

module Shoko
  module Core
    module Models
      # Represents a contiguous run of text with associated inline styles.
      TextSegment = Data.define(:text, :styles) do
        def initialize(text:, styles: nil)
          normalized_styles = Shoko::Shared::HashNormalizer.deep_symbolize(styles) || {}
          super(text: ValueNormalizer.immutable(text.to_s), styles: ValueNormalizer.immutable(normalized_styles))
        end

        def length
          text.to_s.length
        end
      end
    end
  end
end
