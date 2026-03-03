# frozen_string_literal: true

require_relative 'pdb_header_parser'
require_relative 'mobi_header_parser'
require_relative 'exth_parser'
require_relative 'metadata_parser'
require_relative '../../ports/outbound/path_ops'

module Shoko
  module Core
    module BookFormats
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
              return {} unless file_reader
              unless path_ops.is_a?(Shoko::Core::Ports::Outbound::PathOps)
                raise ArgumentError, 'path_ops must implement Core::Ports::Outbound::PathOps'
              end

              data = file_reader.call(path).to_s
              pdb = PdbHeaderParser.new(data)
              record0 = pdb.record_data(0)
              mobi = MobiHeaderParser.new(record0)
              exth = nil

              if mobi.has_exth?
                exth_data = record0.byteslice(mobi.exth_offset..)
                exth = ExthParser.new(exth_data, encoding_name: mobi.encoding_name)
              end

              canonical = MetadataParser.parse(
                mobi: mobi,
                exth: exth,
                fallback_title: fallback_title(path, path_ops: path_ops)
              )
              authors = Array(canonical[:authors]).map(&:to_s).reject(&:empty?)

              {
                title: canonical[:title],
                authors: authors,
                author_str: authors.empty? ? nil : authors.join('; '),
                year: canonical[:year],
                language: canonical[:language]
              }.compact
            rescue ArgumentError
              raise
            rescue Shoko::Error
              {}
            end

            private

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
