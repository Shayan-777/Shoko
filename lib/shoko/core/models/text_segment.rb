# frozen_string_literal: true

require_relative '../../shared/hash_normalizer'

module Shoko
  module Core
    module Models
      # Represents a contiguous run of text with associated inline styles.
      TextSegment = Struct.new(:text, :styles) do
        def initialize(text:, styles: nil)
          super(text: text.to_s, styles: (Shoko::Shared::HashNormalizer.deep_symbolize(styles) || {}).freeze)
        end

        def length
          text.to_s.length
        end
      end
    end
  end
end
