# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Immutable fuzzy-search result with similarity score.
      FuzzyMatch = Data.define(:word, :similarity) do
        def initialize(word:, similarity:)
          super(word: word.to_s.dup.freeze, similarity: similarity.to_f)
        end

        def high_confidence? = similarity >= 0.8

        def medium_confidence? = similarity >= 0.6 && similarity < 0.8

        def low_confidence? = similarity < 0.6
      end
    end
  end
end
