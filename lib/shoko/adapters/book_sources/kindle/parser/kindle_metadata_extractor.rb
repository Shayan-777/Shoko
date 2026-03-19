# frozen_string_literal: true

require_relative 'pdb_header_parser'
require_relative 'mobi_header_parser'
require_relative 'exth_parser'
require_relative 'metadata_parser'
require_relative '../../../../core/ports/outbound/path_ops'

module Shoko
  module Adapters
    module BookSources
      module Kindle
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
            # @param file_reader [#call, nil] binary file reader dependency
            # @param path_ops [#basename, nil] path utility dependency
            # @return [Hash] { title:, authors:, author_str:, year:, language: }
            def from_file(path, file_reader: nil, path_ops: nil, **_)
              validate_dependencies!(file_reader, path_ops)
              canonical = read_canonical_metadata(path, file_reader: file_reader, path_ops: path_ops)
              canonical_metadata_hash(canonical)
            rescue Shoko::Error, ArgumentError, TypeError, IOError, SystemCallError => e
              raise if e.is_a?(Shoko::MalformedMetadataInputError)

              raise Shoko::MalformedMetadataInputError, "Kindle metadata extraction failed for #{path}: #{e.message}"
            end

            private

            def validate_dependencies!(file_reader, path_ops)
              raise ArgumentError, 'file_reader is required' unless file_reader
              return if path_ops.is_a?(Shoko::Core::Ports::Outbound::PathOps)

              raise ArgumentError, 'path_ops must implement Core::Ports::Outbound::PathOps'
            end

            def read_canonical_metadata(path, file_reader:, path_ops:)
              record0 = PdbHeaderParser.new(file_reader.call(path).to_s).record_data(0)
              mobi = MobiHeaderParser.new(record0)

              MetadataParser.parse(
                mobi: mobi,
                exth: build_exth_parser(mobi, record0),
                fallback_title: fallback_title(path, path_ops: path_ops)
              )
            end

            def build_exth_parser(mobi, record0)
              return nil unless mobi.exth?

              exth_data = record0.byteslice(mobi.exth_offset..)
              ExthParser.new(exth_data, encoding_name: mobi.encoding_name)
            end

            def canonical_metadata_hash(canonical)
              authors = Array(canonical[:authors]).map(&:to_s).reject(&:empty?)
              {
                title: canonical[:title],
                authors: authors,
                author_str: authors.empty? ? nil : authors.join('; '),
                year: canonical[:year],
                language: canonical[:language],
              }.compact
            end

            def fallback_title(path, path_ops: nil)
              basename = path_ops.basename(path).to_s
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
  end
end
