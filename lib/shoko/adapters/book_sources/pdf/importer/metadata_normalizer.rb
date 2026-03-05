# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Pdf
        module Importer
          # Normalizes parsed PDF metadata into BookData-compatible keys.
          class MetadataNormalizer
            def self.normalize(canonical)
              authors = normalize_authors(canonical[:authors])

              {
                title: canonical[:title],
                authors: authors,
                author_str: authors.join('; '),
                year: canonical[:year].to_s,
                language: canonical[:language],
              }.compact
            end

            def self.normalize_authors(authors)
              Array(authors).each_with_object([]) do |author, normalized|
                text = author.to_s.strip
                normalized << text unless text.empty?
              end
            end
          end
        end
      end
    end
  end
end
