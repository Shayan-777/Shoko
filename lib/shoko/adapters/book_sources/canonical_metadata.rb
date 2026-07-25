# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      # Canonical book-metadata payload shared by the format importers.
      #
      # The extractors pull metadata from wildly different containers, but the
      # shape they hand onward — and the rule that an empty author list yields
      # no author string, and that blank fields are dropped entirely — is one
      # decision with one home.
      module CanonicalMetadata
        module_function

        # @param canonical [Hash] :title, :authors, :year, :language
        # @return [Hash] compacted metadata payload
        def build(canonical)
          authors = Array(canonical[:authors]).map(&:to_s).reject(&:empty?)
          {
            title: canonical[:title],
            authors: authors,
            author_str: authors.empty? ? nil : authors.join('; '),
            year: canonical[:year],
            language: canonical[:language],
          }.compact
        end
      end
    end
  end
end
