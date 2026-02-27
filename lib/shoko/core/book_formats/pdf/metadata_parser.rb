# frozen_string_literal: true

module Shoko
  module Core
    module BookFormats
      module Pdf
        # Canonical parser for PDF metadata fields.
        class MetadataParser
          class << self
            # @param info [Hash, nil] Raw info dictionary values
            # @return [Hash] canonical metadata hash
            def parse(info = nil, **kwargs)
              payload = normalize_payload(info, kwargs)
              title = normalize_text(payload[:title])
              author = normalize_text(payload[:author])
              year = extract_year(payload[:creation_date])

              {
                title: title,
                authors: author ? [author] : [],
                year: year,
                language: nil,
              }
            end

            private

            def normalize_payload(info, kwargs)
              source = info.is_a?(Hash) ? info : {}
              symbolize_keys(source).merge(kwargs)
            end

            def symbolize_keys(hash)
              hash.each_with_object({}) do |(key, value), acc|
                acc[key.to_sym] = value
              end
            end

            def normalize_text(value)
              return nil unless value

              text = value.to_s.strip
              text.empty? ? nil : text
            end

            def extract_year(value)
              return nil unless value

              match = value.to_s.match(/(\d{4})/)
              match && match[1]
            end
          end
        end
      end
    end
  end
end
