# frozen_string_literal: true

require_relative 'entry'

module Shoko
  module Zip
    # Factory for creating Entry objects from Central Directory data
    class EntryFactory
      def self.create_from_header(normalized_name, header_data)
        Entry.new(
          name: normalized_name,
          compressed_size: header_data[:compressed_size],
          uncompressed_size: header_data[:uncompressed_size],
          crc32: header_data[:crc32],
          compression_method: header_data[:compression_method],
          gp_flags: header_data[:gp_flags],
          local_header_offset: header_data[:local_header_offset]
        )
      end
    end
  end
end
