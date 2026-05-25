# frozen_string_literal: true

require_relative '../../../adapters/storage/json_cache_store'
require_relative '../../../adapters/storage/epub_cache'
require_relative '../../../adapters/storage/cache_pointer_manager'
require_relative '../../../adapters/storage/repositories/cached_library_repository'
require_relative '../../../adapters/storage/repositories/display_metadata_cache_repository'
require_relative '../../../adapters/book_sources/library_scanner'

module Shoko
  module Composition
    module ContainerFactory
      # Registers library scanning infrastructure and cache-backed repositories.
      module PortAndRepositoryRegistrationLibraryServices
        def register_library_services(container)
          register_library_cache_types(container)
          register_cached_library_repository(container)
          register_display_metadata_cache(container)
          register_library_scanner(container)
        end

        private

        def register_library_cache_types(container)
          container.register_singleton(:json_cache_store) do |c|
            Shoko::Adapters::Storage::JsonCacheStore.new(
              cache_root: c.resolve(:cache_paths).cache_root,
              runtime_config: c.resolve(:runtime_config)
            )
          end
          container.register(:json_cache_store_class, Shoko::Adapters::Storage::JsonCacheStore)
          container.register(:epub_cache_class, Shoko::Adapters::Storage::EpubCache)
          container.register(:cache_pointer_manager_class, Shoko::Adapters::Storage::CachePointerManager)
        end

        def register_cached_library_repository(container)
          container.register_singleton(:cached_library_repository) do |c|
            Shoko::Adapters::Storage::Repositories::CachedLibraryRepository.new(
              cache_root: c.resolve(:cache_paths).cache_root,
              store: c.resolve(:json_cache_store),
              runtime_config: c.resolve(:runtime_config),
              manifest_store: c.resolve(:json_cache_store_class),
              cache_class: c.resolve(:epub_cache_class),
              pointer_manager_class: c.resolve(:cache_pointer_manager_class)
            )
          end
        end

        def register_display_metadata_cache(container)
          container.register_singleton(:display_metadata_cache) do |c|
            Shoko::Adapters::Storage::Repositories::DisplayMetadataCacheRepository.new(
              cache_root: c.resolve(:cache_paths).cache_root,
              atomic_file_writer: c.resolve(:atomic_file_writer)
            )
          end
        end

        def register_library_scanner(container)
          container.register_factory(:library_scanner) do |c|
            Shoko::Adapters::BookSources::LibraryScanner.new(
              background_worker_builder: c.resolve(:background_worker_builder),
              logger: c.resolve(:logger),
              book_finder: c.resolve(:book_finder)
            )
          end
        end
      end
    end
  end
end
