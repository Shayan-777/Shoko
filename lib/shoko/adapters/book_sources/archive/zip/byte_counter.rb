# frozen_string_literal: true

module Shoko
  module Zip
    # Tracks remaining bytes during chunk reading
    class ByteCounter
      def initialize(total_bytes)
        @remaining = total_bytes
      end

      attr_reader :remaining

      def remaining_positive?
        @remaining.positive?
      end

      def consume(byte_count)
        @remaining -= byte_count
      end
    end
  end
end
