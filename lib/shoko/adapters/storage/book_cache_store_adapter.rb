# frozen_string_literal: true

require_relative '../../application/ports/outbound/book_cache_store'
require_relative 'epub_cache'

module Shoko
  module Adapters
    module Storage
      # Storage adapter for imported book cache payloads.
      class BookCacheStoreAdapter
        include Shoko::Application::Ports::Outbound::BookCacheStore

        def initialize(cache_class: EpubCache, cache_root: CachePaths.cache_root, runtime_config: nil, logger: nil)
          @cache_class = cache_class
          @cache_root = cache_root
          @runtime_config = runtime_config
          @logger = logger
        end

        def fetch(path, strict: true)
          cache = build_cache(path)
          payload = cache.cache_file? ? cache.read_cache(strict: strict) : cache.load_for_source(strict: strict)
          return nil unless payload

          cache_entry(cache, payload, loaded_from_cache: true)
        end

        def write(path, book_data)
          cache = build_cache(path)
          raise Shoko::CacheLoadError.new(cache.cache_path, 'cache write failed') unless cache.write_book!(book_data)

          payload = cache.load_for_source(strict: true) || cache.read_cache(strict: true)
          raise Shoko::CacheLoadError.new(cache.cache_path, 'cache payload unavailable after write') unless payload

          cache_entry(cache, payload, loaded_from_cache: false)
        end

        private

        def build_cache(path)
          @cache_class.new(path, cache_root: @cache_root, runtime_config: @runtime_config, logger: @logger)
        end

        def cache_entry(cache, payload, loaded_from_cache:)
          Shoko::Application::Ports::Outbound::BookCacheStore::CacheEntry.new(
            book: payload.book,
            cache_path: cache.cache_path,
            source_path: payload.source_path || cache.source_path,
            source_sha: payload.source_sha256 || cache.sha256,
            loaded_from_cache: loaded_from_cache,
            payload: payload
          )
        end
      end
    end
  end
end
