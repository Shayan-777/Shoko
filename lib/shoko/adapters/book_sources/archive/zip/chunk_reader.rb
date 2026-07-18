# frozen_string_literal: true

require_relative 'byte_counter'
require_relative 'error'
require_relative 'sizes'

module Shoko
  module Zip
    # Tracks remaining bytes during chunk reading
    class ChunkReader
      def initialize(io, total_bytes)
        @io = io
        @counter = ByteCounter.new(total_bytes)
      end

      def read_all_chunks
        chunks = []
        while @counter.remaining_positive?
          chunk = read_next_chunk
          chunks << chunk
        end
        chunks
      end

      def process_chunks_with(inflater, output)
        while @counter.remaining_positive?
          chunk = read_next_chunk
          output.append(inflater.inflate(chunk))
        end
      end

      private

      def read_next_chunk
        chunk = read_chunk_from_io
        validate_chunk(chunk)
        @counter.consume(chunk.bytesize)
        chunk
      end

      def read_chunk_from_io
        chunk_size = calculate_chunk_size
        @io.read(chunk_size)
      end

      def calculate_chunk_size
        remaining = @counter.remaining
        [remaining, Sizes::READ_CHUNK].min
      end

      def validate_chunk(chunk)
        raise Error, 'truncated compressed data' unless chunk && !chunk.empty?
      end
    end
  end
end
