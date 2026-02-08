# frozen_string_literal: true

module Shoko
  module Adapters::Storage
    class BookCachePipeline
      # Bundles payload and cache status for cache session operations.
      class PayloadContext
        attr_reader :payload, :cache_status

        def initialize(payload:, cache_status:)
          @payload = payload
          @cache_status = cache_status
        end
      end

      private_constant :PayloadContext
    end
  end
end
