# frozen_string_literal: true

require 'shoko/adapters/book_sources/kindle/parser/pdb_header_parser'

module Shoko
  module Adapters
    module BookSources
      module Kindle
        # Reads embedded images out of a Mobipocket/KF8 container by their
        # `image0001.jpg` style logical name (the form the Kindle importer
        # rewrites `kindle:embed:0001` / MOBI6 `recindex` references into).
        #
        # MOBI/KF8 stores images as ordinary PDB records whose payload begins
        # with a known image signature; KF8 in particular leaves the MOBI
        # header's first-image field unset, so the records are located by
        # scanning for those signatures. The Nth such record is image N.
        class KindleImageSource
          JPEG = "\xFF\xD8\xFF".b
          PNG  = "\x89PNG".b
          GIF  = 'GIF8'
          ENTRY_PATTERN = /image0*(\d+)\.(?:jpe?g|png|gif)\z/i

          def initialize(pdb_parser: PdbHeaderParser, logger: nil)
            @pdb_parser = pdb_parser
            @logger = logger
            @records_by_path = {}
          end

          # @param path [String] filesystem path to the .mobi/.azw/.azw3 file
          # @param entry_path [String] logical image name, e.g. "image0001.jpg"
          # @return [String, nil] raw image bytes, or nil when not found
          def fetch(path, entry_path)
            index = image_index(entry_path)
            return nil unless index && path && File.file?(path)

            records = image_records(path)
            records[index - 1]
          end

          private

          def image_index(entry_path)
            match = entry_path.to_s.match(ENTRY_PATTERN)
            match && match[1].to_i
          end

          # Memoized per path: one PDB scan serves every image of a book.
          def image_records(path)
            @records_by_path[path] ||= scan_image_records(path)
          end

          # Reading and parsing an external container is a resilient boundary:
          # a malformed/unreadable file (parse error, I/O failure) degrades to
          # "no images" so the book still opens, rather than crashing the render.
          def scan_image_records(path)
            pdb = @pdb_parser.new(File.binread(path))
            (0...pdb.num_records).filter_map do |index|
              data = pdb.record_data(index)
              data if image_payload?(data)
            end
          # resilient-boundary
          rescue StandardError => e
            record_scan_error(path, e)
            []
          end

          def record_scan_error(path, error)
            @logger&.debug('kindle_image_source.scan_failed', path: path.to_s,
                                                              error: error.class.name, message: error.message)
          end

          def image_payload?(data)
            data.to_s.start_with?(JPEG, PNG, GIF)
          end
        end
      end
    end
  end
end
