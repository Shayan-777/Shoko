# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Kindle
        class KindleImporter
          # Metadata extraction helpers for PDB/MOBI/EXTH-backed Kindle files.
          module MetadataSupport
            private

            def extract_metadata(record0)
              canonical = Adapters::BookSources::Kindle::MetadataParser.parse(
                mobi: @mobi,
                exth: extract_exth(record0),
                fallback_title: nil
              )
              build_metadata(canonical)
            end

            def extract_exth(record0)
              return nil unless @mobi.exth?

              exth_data = record0.byteslice(@mobi.exth_offset..)
              return nil unless exth_data && exth_data.bytesize >= 12

              Adapters::BookSources::Kindle::ExthParser.new(exth_data, encoding_name: @mobi.encoding_name)
            end

            def build_metadata(canonical)
              authors = Array(canonical[:authors]).map(&:to_s).reject(&:empty?)
              title = canonical[:title].to_s
              title = nil if title.empty?

              metadata = { title: title, authors: authors, language: canonical[:language], year: canonical[:year] }
              metadata[:author_str] = authors.join('; ') unless authors.empty?
              metadata.compact
            end
          end
        end
      end
    end
  end
end
