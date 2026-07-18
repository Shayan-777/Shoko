# frozen_string_literal: true

require 'zlib'
require_relative 'error'

module Shoko
  module Zip
    # Represents decompressed entry data with metadata
    class DecompressedData
      attr_reader :entry, :data

      def initialize(entry, data)
        @entry = entry
        @data = data
      end

      def verify_size
        expected_size = entry.uncompressed_size
        return unless expected_size&.positive?
        return if data.bytesize == expected_size

        raise Error, 'size mismatch after decompression'
      end

      def verify_crc32
        expected_crc32 = entry.crc32
        return if expected_crc32.nil?

        actual_crc32 = ::Zlib.crc32(data)
        return if actual_crc32 == expected_crc32

        raise Error, "crc32 mismatch for entry: #{entry.name}"
      end

      def register_with_limits(limits)
        limits.register_uncompressed_bytes(entry, data.bytesize)
        encode_as_binary
      end

      def finalize_and_register(limits)
        verify_size
        verify_crc32
        register_with_limits(limits)
      end

      private

      def encode_as_binary
        data.force_encoding(Encoding::BINARY)
      end
    end
  end
end
