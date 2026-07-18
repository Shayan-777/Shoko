# frozen_string_literal: true

require_relative 'error'

module Shoko
  module Zip
    # Parser for End of Central Directory record
    class EOCDParser
      def self.parse(tail_data, eocd_index)
        new(tail_data, eocd_index).parse
      end

      def self.extract_directory_info(eocd_record)
        cd_size = eocd_record.byteslice(12, 4).unpack1('V')
        cd_offset = eocd_record.byteslice(16, 4).unpack1('V')
        [cd_offset, cd_size]
      end

      def initialize(tail_data, eocd_index)
        @tail_data = tail_data
        @eocd_index = eocd_index
      end

      def parse
        eocd_record = extract_eocd_record
        validate_eocd_record(eocd_record)
        self.class.extract_directory_info(eocd_record)
      end

      private

      def extract_eocd_record
        @tail_data.byteslice(@eocd_index, 22)
      end

      def validate_eocd_record(eocd_record)
        raise Error, 'truncated EOCD' unless eocd_record && eocd_record.bytesize == 22
      end
    end
  end
end
