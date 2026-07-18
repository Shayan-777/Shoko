# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Fuzzy search result with similarity score
      class FuzzyMatch
        attr_reader :word, :similarity

        def initialize(word:, similarity:)
          @word = word.to_s.freeze
          @similarity = similarity.to_f
          # Born frozen: matches are placed into the state tree, whose value
          # contract admits opaque objects only when they are immutable.
          freeze
        end

        def high_confidence?
          similarity >= 0.8
        end

        def medium_confidence?
          similarity >= 0.6 && similarity < 0.8
        end

        def low_confidence?
          similarity < 0.6
        end
      end
    end
  end
end
