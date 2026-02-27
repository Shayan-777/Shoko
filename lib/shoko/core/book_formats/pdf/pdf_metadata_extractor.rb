# frozen_string_literal: true

require_relative 'pdf_reader'
require_relative 'metadata_parser'

module Shoko
  module Core
    module BookFormats
      module Pdf
        # Extracts metadata (title, author, year, etc.) from a PDF's Info dictionary.
        class PdfMetadataExtractor
          class << self
            # @param path [String] path to .pdf file
            # @param file_reader [#call, nil] callable to read binary data
            # @return [Hash] normalized metadata
            def from_file(path, file_reader: nil)
              return {} unless file_reader

              reader = PdfReader.new(file_reader.call(path))
              info_num = reader.info_obj_num
              return {} unless info_num

              info_raw = reader.read_object_raw(info_num)
              return {} unless info_raw

              normalize(MetadataParser.parse(extract_info(reader, info_raw)))
            rescue StandardError
              {}
            end

            private

            def extract_info(reader, info_raw)
              {
                title: reader.dict_value(info_raw, 'Title'),
                author: reader.dict_value(info_raw, 'Author'),
                creator: reader.dict_value(info_raw, 'Creator'),
                creation_date: reader.dict_value(info_raw, 'CreationDate'),
                keywords: reader.dict_value(info_raw, 'Keywords'),
              }
            end

            def normalize(meta)
              return {} unless meta.is_a?(Hash)

              authors = Array(meta[:authors]).compact.map(&:to_s).map(&:strip).reject(&:empty?)
              {
                authors: authors,
                author_str: authors.join('; '),
                year: meta[:year].to_s,
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
