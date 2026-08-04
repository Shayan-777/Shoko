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
        prospective_bytes = @data.bytesize + chunk.bytesize
        @limits.enforce_uncompressed_budget(@entry, prospective_bytes)
        @data << chunk
      end

      def finalize(inflater)
        append(inflater.finish)
        @data
      end
    end
  end
end
