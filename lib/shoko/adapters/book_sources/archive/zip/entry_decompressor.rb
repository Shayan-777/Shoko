# frozen_string_literal: true

require 'zlib'
require_relative 'chunk_reader'
require_relative 'decompression_output'
require_relative 'error'

module Shoko
  module Zip
    # Handles decompression of deflated ZIP entries
    class EntryDecompressor
      def self.create_inflater
        ::Zlib::Inflate.new(-::Zlib::MAX_WBITS)
      end

      def initialize(io, limits)
        @io = io
        @limits = limits
      end

      def inflate_deflated_entry(entry)
        remaining_bytes = entry.compressed_size.to_i
        with_inflater { |inflater| decompress_all(inflater, entry, remaining_bytes) }
      end

      private

      def with_inflater
        inflater = self.class.create_inflater
        yield inflater
      rescue ::Zlib::DataError => e
        raise Error, "invalid deflate data: #{e.message}"
      ensure
        close_inflater(inflater)
      end

      def close_inflater(inflater)
        inflater&.close
      rescue IOError, SystemCallError
        # best-effort inflater cleanup
      end

      def decompress_all(inflater, entry, remaining_bytes)
        output = DecompressionOutput.new(@limits, entry)
        reader = ChunkReader.new(@io, remaining_bytes)
        reader.process_chunks_with(inflater, output)
        output.finalize(inflater)
      end
    end
  end
end
