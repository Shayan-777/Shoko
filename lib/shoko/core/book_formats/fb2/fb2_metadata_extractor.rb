# frozen_string_literal: true

require 'rexml/document'
require_relative 'metadata_parser'

module Shoko
  module Core::BookFormats::Fb2
    # Lightweight extractor for FB2 metadata (title, authors, year, language).
    # Opens the file and reads just the <description> block without loading
    # chapter content.
    class Fb2MetadataExtractor
      class << self
        # @param path [String] path to .fb2 or .fb2.zip file
        # @param text_reader [#call, nil] UTF-8 text file reader dependency
        # @param zip_entry_reader [#call, nil] reader for archive entry suffix
        # @return [Hash] normalized metadata
        def from_file(path, text_reader: nil, zip_entry_reader: nil, **_)
          xml = read_fb2(path, text_reader: text_reader, zip_entry_reader: zip_entry_reader)
          return {} unless xml

          stripped = xml.gsub(/\s+xmlns\s*=\s*["'][^"']*["']/, '')
          doc = REXML::Document.new(stripped)
          normalize(MetadataParser.parse_document(doc))
        rescue StandardError
          {}
        end

        private

        def read_fb2(path, text_reader:, zip_entry_reader:)
          lower = path.to_s.downcase
          if lower.end_with?('.fb2.zip')
            return nil unless zip_entry_reader

            zip_entry_reader.call(path, '.fb2')
          else
            return nil unless text_reader

            text_reader.call(path)
          end
        rescue StandardError
          nil
        end

        def normalize(meta)
          return {} unless meta.is_a?(Hash)

          authors = Array(meta[:authors]).compact.map(&:to_s).reject(&:empty?)
          {
            authors: authors,
            author_str: authors.join('; '),
            year: (meta[:year] || '').to_s[0, 4],
            title: meta[:title],
            language: meta[:language],
          }
        end
      end
    end
  end
end
