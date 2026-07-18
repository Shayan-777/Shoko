# frozen_string_literal: true

require_relative 'file'

module Shoko
  module Zip
    # Extracts variable-length fields from Local File Header
    class LocalFileHeaderParser
      LOCAL_HEADER_LENGTH_INDICES = [-2, -1].freeze

      def self.extract_lengths(header_bytes)
        field_values = header_bytes.unpack('v v v v v V V V v v')
        [field_values[LOCAL_HEADER_LENGTH_INDICES[0]], field_values[LOCAL_HEADER_LENGTH_INDICES[1]]]
      end
    end
  end
end
