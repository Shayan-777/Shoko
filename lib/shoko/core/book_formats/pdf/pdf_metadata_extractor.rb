# frozen_string_literal: true

require_relative 'pdf_reader'

module Shoko
  module Core::BookFormats::Pdf
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

          normalize(extract_info(reader, info_raw))
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

          author = decode_pdf_string(meta[:author])
          authors = author ? [author] : []
          year = extract_year(meta[:creation_date])

          {
            authors: authors,
            author_str: authors.join('; '),
            year: year.to_s,
            title: decode_pdf_string(meta[:title]),
            language: nil,
          }
        end

        def decode_pdf_string(value)
          return nil unless value

          str = value.to_s.strip
          str.empty? ? nil : str
        end

        def extract_year(date_str)
          return nil unless date_str

          # PDF dates: D:YYYYMMDDHHmmSS+TZ or just YYYY...
          match = date_str.to_s.match(/(\d{4})/)
          match ? match[1] : nil
        end
      end
    end
  end
end
