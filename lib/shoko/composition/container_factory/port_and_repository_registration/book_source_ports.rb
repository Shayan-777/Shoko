# frozen_string_literal: true

require_relative '../../../adapters/storage/config_storage_adapter'
require_relative '../../../adapters/storage/atomic_file_writer'
require_relative '../../../adapters/book_sources/book_finder'
require_relative '../../../adapters/book_sources/book_file_probe'
require_relative '../../../adapters/book_sources/folder_scanner'
require_relative '../../../adapters/book_sources/format_registry'
require_relative '../../../adapters/book_sources/book_importer_resolver_adapter'
require_relative '../../../adapters/book_sources/metadata_reader_adapter'
require_relative '../../format_registry_composition'

module Shoko
  module Composition
    module ContainerFactory
      # Registers book source and metadata discovery ports for composition wiring.
      module PortAndRepositoryRegistrationBookSourcePorts
        private

        def register_book_source_ports(container)
          Shoko::Composition::FormatRegistryComposition.register!
          register_book_discovery_ports(container)
          register_metadata_ports(container)
          register_import_ports(container)
        end

        def register_book_discovery_ports(container)
          register_config_storage_ports(container)
          register_book_finder_port(container)
          register_folder_scanner_port(container)
        end

        def register_config_storage_ports(container)
          container.register_singleton(:config_storage) do |_c|
            Shoko::Adapters::Storage::ConfigStorageAdapter.new
          end
          container.register_singleton(:book_file_probe) do |_c|
            Shoko::Adapters::BookSources::BookFileProbe.new
          end
        end

        def register_book_finder_port(container)
          container.register_singleton(:book_finder) do |c|
            config_storage = c.resolve(:config_storage)
            Shoko::Adapters::BookSources::BookFinder.new(
              config_root: config_storage.config_dir,
              cache_writer: Shoko::Adapters::Storage::AtomicFileWriter,
              book_file_probe: c.resolve(:book_file_probe),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_folder_scanner_port(container)
          container.register_singleton(:folder_scanner) do |c|
            Shoko::Adapters::BookSources::FolderScanner.new(
              format_registry: Shoko::Adapters::BookSources::FormatRegistry,
              book_file_probe: c.resolve(:book_file_probe)
            )
          end
        end

        def register_metadata_ports(container)
          container.register_singleton(:metadata_reader) do |c|
            Shoko::Adapters::BookSources::MetadataReaderAdapter.new(
              file_probe: c.resolve(:file_probe),
              path_ops: c.resolve(:path_ops),
              file_reader: c.resolve(:binary_file_reader),
              text_reader: c.resolve(:utf8_file_reader),
              zip_open: c.resolve(:zip_open),
              zip_entry_reader: c.resolve(:zip_entry_reader)
            )
          end
        end

        def register_import_ports(container)
          container.register_singleton(:book_importer_resolver) do |_c|
            Shoko::Adapters::BookSources::BookImporterResolverAdapter.new(
              format_registry: Shoko::Adapters::BookSources::FormatRegistry
            )
          end
        end
      end
    end
  end
end
