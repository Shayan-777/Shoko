# frozen_string_literal: true

module Shoko
  module Zip
    # Parser for Central Directory Fixed Header fields
    class CentralDirectoryHeaderParser
      FIELD_INDICES = {
        gp_flags: 2,
        compression_method: 3,
        crc32: 6,
        compressed_size: 7,
        uncompressed_size: 8,
        name_length: 9,
        extra_length: 10,
        comment_length: 11,
        local_header_offset: 15,
      }.freeze

      def self.extract_named_fields(field_values)
        FIELD_INDICES.transform_values { |index| field_values[index] }
      end

      def initialize(header_bytes)
        @header_bytes = header_bytes
      end

      def parse
        field_values = @header_bytes.unpack('v v v v v v V V V v v v v v V V')
        self.class.extract_named_fields(field_values)
      end
    end
  end
end
