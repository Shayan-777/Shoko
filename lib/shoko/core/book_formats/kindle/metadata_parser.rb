# frozen_string_literal: true

module Shoko
  module Core
    module BookFormats
      module Kindle
        # Canonical parser for Kindle metadata from MOBI/EXTH fields.
        class MetadataParser
          class << self
            # @param mobi [Object] Parsed MOBI header
            # @param exth [Object, nil] Parsed EXTH metadata
            # @param fallback_title [String, nil] Fallback title from file name
            # @return [Hash] canonical metadata hash
            def parse(mobi:, exth:, fallback_title:)
              {
                title: resolve_title(mobi, exth, fallback_title),
                authors: resolve_authors(exth),
                year: resolve_year(exth),
                language: normalize_text(exth&.language),
              }
            rescue StandardError
              {
                title: normalize_text(fallback_title),
                authors: [],
                year: nil,
                language: nil,
              }
            end

            private

            def resolve_title(mobi, exth, fallback_title)
              normalize_text(exth&.updated_title) ||
                normalize_text(mobi&.full_name) ||
                normalize_text(fallback_title)
            end

            def resolve_authors(exth)
              Array(exth&.authors).map { |author| normalize_text(author) }.compact
            end

            def resolve_year(exth)
              date = exth&.publishing_date
              return nil unless date

              match = date.to_s.match(/\d{4}/)
              match && match[0]
            end

            def normalize_text(value)
              return nil unless value

              text = value.to_s.strip
              text.empty? ? nil : text
            end
          end
        end
      end
    end
  end
end
