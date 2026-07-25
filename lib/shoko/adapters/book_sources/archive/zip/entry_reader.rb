# frozen_string_literal: true

require_relative 'exact_io'
require_relative 'decompressed_data'
require_relative 'entry_decompressor'
require_relative 'error'
require_relative 'local_file_header_parser'
require_relative 'signatures'

module Shoko
  module Zip
    # Handles reading entry data from ZIP file
    class EntryReader
      def initialize(io, limits)
        @io = io
        @limits = limits
      end

      def read_entry(entry)
        seek_to_entry_data(entry)
        raw_data = read_entry_payload(entry)
        decompressed = DecompressedData.new(entry, raw_data)
        decompressed.finalize_and_register(@limits)
      end

      private

      def seek_to_entry_data(entry)
        @io.seek(entry.local_header_offset, ::IO::SEEK_SET)
        ExactIo.verify_signature(@io, Signatures::LOCAL_FILE, 'invalid local file header signature')
        skip_local_file_header
      end

      def skip_local_file_header
        header = ExactIo.read_exact(@io, 26, error_message: 'truncated local file header')
        name_length, extra_length = LocalFileHeaderParser.extract_lengths(header)
        @io.seek(name_length + extra_length, ::IO::SEEK_CUR)
      end

      def read_entry_payload(entry)
        compression_method = entry.compression_method
        case compression_method
        when 0 then read_stored_entry(entry)
        when 8 then decompress_deflated_entry(entry)
        else raise Error, "unsupported compression method: #{compression_method}"
        end
      end

      def read_stored_entry(entry)
        compressed_size = entry.compressed_size
        data = @io.read(compressed_size)
        return data if data && data.bytesize == compressed_size

        raise Error, 'truncated compressed data'
      end

      def decompress_deflated_entry(entry)
        decompressor = EntryDecompressor.new(@io, @limits)
        decompressor.inflate_deflated_entry(entry)
      end
    end
  end
end
