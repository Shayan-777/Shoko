# frozen_string_literal: true

require_relative '../../../adapters/storage/data_cleanup_adapter'
require_relative '../../../adapters/storage/cache_manager_adapter'
require_relative '../../../adapters/storage/cache_paths'
require_relative '../../../adapters/storage/book_cache_store_adapter'
require_relative '../../../adapters/storage/file_probe_adapter'
require_relative '../../../adapters/storage/path_ops_adapter'

module Shoko
  module Composition
    module ContainerFactory
      # Registers storage and cleanup ports for composition wiring.
      module PortAndRepositoryRegistrationStoragePorts
        private

        def register_storage_ports(container)
          register_cleanup_ports(container)
          register_book_cache_ports(container)
          register_file_system_ports(container)
        end

        def register_cleanup_ports(container)
          container.register_singleton(:data_cleanup) do |_c|
            Shoko::Adapters::Storage::DataCleanupAdapter.new
          end
          container.register_singleton(:cache_manager) do |c|
            Shoko::Adapters::Storage::CacheManagerAdapter.new(
              epub_cache_clearer: -> { c.resolve(:book_finder).clear_cache },
              cache_path_provider: Shoko::Adapters::Storage::CachePaths
            )
          end
        end

        def register_file_system_ports(container)
          container.register_singleton(:file_probe) do |_c|
            Shoko::Adapters::Storage::FileProbeAdapter.new
          end
          container.register_singleton(:path_ops) do |_c|
            Shoko::Adapters::Storage::PathOpsAdapter.new
          end
        end

        def register_book_cache_ports(container)
          container.register_singleton(:book_cache_store) do |c|
            Shoko::Adapters::Storage::BookCacheStoreAdapter.new(
              cache_root: c.resolve(:cache_paths).cache_root,
              runtime_config: c.resolve(:runtime_config),
              logger: c.resolve(:logger)
            )
          end
        end
      end
    end
  end
end
