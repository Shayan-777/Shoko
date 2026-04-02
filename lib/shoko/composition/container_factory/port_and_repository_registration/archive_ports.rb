# frozen_string_literal: true

require_relative '../../../adapters/book_sources/archive/zip_reader'

module Shoko
  module Composition
    module ContainerFactory
      # Registers archive-related ports for composition wiring.
      module PortAndRepositoryRegistrationArchivePorts
        private

        def register_archive_ports(container)
          register_archive_readers(container)
          register_zip_ports(container)
        end

        def register_archive_readers(container)
          container.register_singleton(:archive_reader) do |_c|
            Shoko::Adapters::BookSources::Archive::ZipReader
          end
          container.register_singleton(:binary_file_reader) do |_c|
            ->(path) { File.binread(path) }
          end
          container.register_singleton(:utf8_file_reader) do |_c|
            ->(path) { File.read(path, encoding: 'UTF-8') }
          end
        end

        def register_zip_ports(container)
          register_zip_open_port(container)
          register_zip_entry_reader_port(container)
        end

        def register_zip_open_port(container)
          container.register_singleton(:zip_open) do |c|
            archive_reader = c.resolve(:archive_reader)
            runtime_config = c.resolve(:runtime_config)
            lambda do |path, &block|
              archive_reader.open(path, runtime_config: runtime_config, &block)
            end
          end
        end

        def register_zip_entry_reader_port(container)
          container.register_singleton(:zip_entry_reader) do |c|
            archive_reader = c.resolve(:archive_reader)
            runtime_config = c.resolve(:runtime_config)
            build_zip_entry_reader(archive_reader, runtime_config)
          end
        end

        def build_zip_entry_reader(archive_reader, runtime_config)
          lambda do |path, suffix|
            archive_reader.open(path, runtime_config: runtime_config) do |zip|
              entry = zip.entries.find { |item| item.name.downcase.end_with?(suffix.to_s.downcase) }
              entry ? zip.read(entry.name) : nil
            end
          end
        end
      end
    end
  end
end
