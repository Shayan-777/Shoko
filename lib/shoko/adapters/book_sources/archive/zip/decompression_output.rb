# frozen_string_literal: true

module Shoko
  module Zip
    # Accumulates decompressed data with budget enforcement
    class DecompressionOutput
      def initialize(limits, entry)
        @limits = limits
        @entry = entry
        @data = +''
      end

      def append(chunk)
        @data << chunk
        @limits.enforce_uncompressed_budget(@entry, @data.bytesize)
      end

      def finalize(inflater)
        @data << inflater.finish
        @data
      end
    end
  end
end
