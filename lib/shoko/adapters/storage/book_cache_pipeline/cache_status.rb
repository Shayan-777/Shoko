# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      class BookCachePipeline
        # Tracks whether a payload originated from cache.
        class CacheStatus
          def self.hit(cache_marker)
            new(cache_marker)
          end

          def self.miss
            new(nil)
          end

          def initialize(cache_marker)
            @cache_marker = cache_marker
          end

          def mark_rebuilt
            @cache_marker = nil
          end

          def loaded_from_cache?
            !!@cache_marker
          end
        end

        private_constant :CacheStatus
      end
    end
  end
end
