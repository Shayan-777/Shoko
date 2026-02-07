# frozen_string_literal: true

require_relative 'pdb_header_parser'
require_relative 'mobi_header_parser'
require_relative 'exth_parser'

module Shoko
  module Core::BookFormats::Kindle
    # Lightweight metadata extractor for Kindle/Mobipocket files.
    # Implements the `self.from_file(path)` interface used by FormatRegistry.
    #
    # Reads only the PDB header and record 0 (MOBI + EXTH headers) to
    # quickly extract title, author, year, and language without
    # decompressing the full text content.
    module KindleMetadataExtractor
      class << self
        # Extract metadata from a .mobi, .azw, or .azw3 file.
        #
        # @param path [String] path to the ebook file
        # @return [Hash] { title:, authors:, author_str:, year:, language: }
        def from_file(path)
          data = File.binread(path)
          pdb = PdbHeaderParser.new(data)
          record0 = pdb.record_data(0)
          mobi = MobiHeaderParser.new(record0)

          metadata = { title: nil, authors: [], author_str: nil, year: nil, language: nil }

          if mobi.has_exth?
            exth_data = record0.byteslice(mobi.exth_offset..)
            exth = ExthParser.new(exth_data, encoding_name: mobi.encoding_name)
            extract_from_exth(exth, metadata)
          end

          # Title fallback: EXTH updated_title > MOBI full_name > filename
          metadata[:title] ||= mobi.full_name
          metadata[:title] = nil if metadata[:title]&.empty?
          metadata[:title] ||= fallback_title(path)

          metadata[:author_str] = metadata[:authors].join('; ') unless metadata[:authors].empty?

          metadata.compact
        rescue StandardError
          {}
        end

        private

        def extract_from_exth(exth, metadata)
          metadata[:title] = exth.updated_title
          metadata[:authors] = exth.authors if exth.authors.any?
          metadata[:language] = exth.language

          date = exth.publishing_date
          if date
            year_match = date.match(/\d{4}/)
            metadata[:year] = year_match[0] if year_match
          end
        end

        def fallback_title(path)
          basename = File.basename(path)
          # Strip known extensions
          %w[.mobi .azw3 .azw].each do |ext|
            basename = basename[0..-(ext.length + 1)] if basename.downcase.end_with?(ext)
          end
          basename.tr('_', ' ').strip
        end
      end
    end
  end
end
