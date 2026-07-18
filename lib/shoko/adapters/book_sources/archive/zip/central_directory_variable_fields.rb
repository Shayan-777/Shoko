# frozen_string_literal: true

require_relative 'name_normalizer'

module Shoko
  module Zip
    # Extracts variable-length fields from Central Directory entry
    class CentralDirectoryVariableFields
      def initialize(io, header_data)
        @io = io
        @header_data = header_data
      end

      def read_and_skip
        entry_name = read_entry_name
        skip_extra_and_comment
        entry_name
      end

      private

      def read_entry_name
        name_length = @header_data[:name_length]
        raw_name = @io.read(name_length) || ''
        NameNormalizer.normalize(raw_name)
      end

      def skip_extra_and_comment
        extra_length = @header_data[:extra_length]
        comment_length = @header_data[:comment_length]
        total_skip = extra_length + comment_length
        skip_bytes(total_skip)
      end

      def skip_bytes(byte_count)
        return if byte_count.to_i <= 0

        @io.seek(byte_count, ::IO::SEEK_CUR)
      end
    end
  end
end
