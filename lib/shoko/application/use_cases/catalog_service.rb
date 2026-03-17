# frozen_string_literal: true

require_relative '../../core/ports/outbound/library_scanner'
require_relative '../../core/ports/outbound/metadata_reader'

module Shoko
  module Application
    module UseCases
      # Facade providing catalog data (cached books, scan status, metadata) to higher layers.
      # Wraps the infrastructure scanner/metadata helpers so presentation never touches them directly.
      class CatalogService
        def initialize(library_scanner:, metadata_reader:, cached_library_repository: nil,
                       recent_files_repository: nil, logger: nil, file_probe: nil)
          unless library_scanner.is_a?(Shoko::Core::Ports::Outbound::LibraryScanner)
            raise ArgumentError, 'library_scanner must implement Core::Ports::Outbound::LibraryScanner'
          end
          unless metadata_reader.is_a?(Shoko::Core::Ports::Outbound::MetadataReader)
            raise ArgumentError, 'metadata_reader must implement Core::Ports::Outbound::MetadataReader'
          end

          @scanner = library_scanner
          @cached_library_repository = cached_library_repository
          @recent_files_repository = recent_files_repository
          @metadata_reader = metadata_reader
          @logger = logger
          @file_probe = file_probe
          @metadata_cache = {}
        end

        def load_cached
          @scanner.load_cached
        end

        def cached_library_entries
          return [] unless @cached_library_repository

          entries = Array(@cached_library_repository.list_entries).map do |entry|
            normalize_hash(entry, context: 'cached_library_entry')
          end
          return [] if entries.empty?

          recent_index = index_recent_by_path
          entries.each do |entry|
            path = entry[:book_path] || entry[:epub_path]
            entry[:last_accessed] = recent_index[path] if path
          end
          entries
        end

        def start_scan(force: false)
          @scanner.start_scan(force: force)
        end

        def process_results
          results = @scanner.process_results
          update_entries(results) if results
          results
        end

        def entries
          @scanner.entries || []
        end

        def update_entries(entries)
          @scanner.update_entries(entries)
          clear_metadata_cache
        end

        def scan_status
          @scanner.scan_status
        end

        def scan_message
          @scanner.scan_message
        end

        def update_scan_state(status:, message:)
          @scanner.update_scan_state(status: status, message: message)
        end

        def reset_after_wipe(message:)
          update_entries([])
          update_scan_state(status: :idle, message: message)
        end

        def cleanup
          @scanner.cleanup
        end

        def metadata_for(path)
          return {} unless path

          @metadata_cache[path] ||= normalize_hash(@metadata_reader.extract_metadata(path), context: 'book_metadata')
        end

        def size_for(path)
          return 0 unless path

          @file_probe&.size(path) || 0
        end

        def clear_metadata_cache
          @metadata_cache.clear
        end

        private

        def index_recent_by_path
          items = @recent_files_repository&.load
          Array(items).each_with_object({}) do |recent_item, acc|
            item = normalize_hash(recent_item, context: 'recent_file_entry')
            path = item[:path]
            accessed = item[:accessed]
            acc[path] = accessed if path && accessed
          end
        end

        def normalize_hash(value, context:)
          raise ArgumentError, "#{context} must be a Hash, got #{value.class}" unless value.is_a?(Hash)

          value.each_with_object({}) do |(key, inner_value), acc|
            normalized_key = key.is_a?(String) ? key.to_sym : key
            acc[normalized_key] = inner_value
          end
        end
      end
    end
  end
end
