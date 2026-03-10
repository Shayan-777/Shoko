# frozen_string_literal: true

require 'rexml/document'
require_relative 'metadata_parser'

module Shoko
  module Adapters
    module BookSources
      module Fb2
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
              if xml.to_s.strip.empty?
                raise Shoko::MalformedMetadataInputError, "FB2 metadata source is empty for #{path}"
              end

              stripped = xml.gsub(/\s+xmlns\s*=\s*["'][^"']*["']/, '')
              doc = REXML::Document.new(stripped)
              normalize(MetadataParser.parse_document(doc))
            rescue Shoko::Error, ArgumentError, TypeError => e
              raise if e.is_a?(Shoko::MalformedMetadataInputError)

              raise Shoko::MalformedMetadataInputError, "FB2 metadata extraction failed for #{path}: #{e.message}"
            end

            private

            def read_fb2(path, text_reader:, zip_entry_reader:)
              lower = path.to_s.downcase
              if lower.end_with?('.fb2.zip')
                raise ArgumentError, 'zip_entry_reader is required for .fb2.zip files' unless zip_entry_reader

                zip_entry_reader.call(path, '.fb2')
              else
                raise ArgumentError, 'text_reader is required for .fb2 files' unless text_reader

                text_reader.call(path)
              end
            end

            def normalize(meta)
              unless meta.is_a?(Hash)
                raise Shoko::MalformedMetadataInputError, "FB2 metadata parser returned #{meta.class}"
              end

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
  end
end
