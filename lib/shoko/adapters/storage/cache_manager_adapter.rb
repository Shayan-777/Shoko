# frozen_string_literal: true

require_relative '../../core/ports/outbound/cache_manager'

module Shoko
  module Adapters
    module Storage
      # Adapter implementing the CacheManager port.
      # Dependencies injected to avoid coupling to sibling adapters.
      class CacheManagerAdapter
        include Core::Ports::Outbound::CacheManager

        def initialize(epub_cache_clearer:, cache_path_provider:)
          @epub_cache_clearer = epub_cache_clearer
          @cache_path_provider = cache_path_provider
        end

        def clear_epub_cache
          @epub_cache_clearer.call
        end

        def cache_root
          @cache_path_provider.cache_root
        end
      end
    end
  end
end
