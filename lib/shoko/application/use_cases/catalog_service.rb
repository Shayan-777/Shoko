# frozen_string_literal: true

require_relative '../../core/services/base_service'
require_relative '../../adapters/book_sources/epub/parsers/metadata_extractor'
require_relative '../../adapters/storage/recent_files'
require_relative '../../adapters/storage/repositories/cached_library_repository'

module Shoko
  module Application::UseCases
    # Facade providing catalog data (cached books, scan status, metadata) to higher layers.
    # Wraps the infrastructure scanner/metadata helpers so presentation never touches them directly.
    class CatalogService < BaseService
      def initialize(dependencies)
        super
        @scanner = resolve(:library_scanner)
        @cached_library_repository = resolve(:cached_library_repository) if registered?(:cached_library_repository)
        @metadata_cache = {}
      end

      def required_dependencies
        [:library_scanner]
      end

      def load_cached
        @scanner.load_cached
      end

      def cached_library_entries
        return [] unless @cached_library_repository

        entries = @cached_library_repository.list_entries
        return [] if entries.empty?

        recent_index = index_recent_by_path
        entries.each do |entry|
          path = entry[:epub_path] || entry['epub_path']
          entry[:last_accessed] = recent_index[path] if path
        end
        entries
      rescue StandardError
        []
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
        @scanner.epubs || []
      end

      def update_entries(entries)
        @scanner.epubs = entries
        clear_metadata_cache
      end

      def scan_status
        @scanner.scan_status
      end

      def scan_status=(value)
        @scanner.scan_status = value
      end

      def scan_message
        @scanner.scan_message
      end

      def scan_message=(value)
        @scanner.scan_message = value
      end

      def cleanup
        @scanner.cleanup if @scanner.respond_to?(:cleanup)
      end

      def metadata_for(path)
        return {} unless path

        @metadata_cache[path] ||= begin
          Adapters::BookSources::Epub::Parsers::MetadataExtractor.from_epub(path)
        rescue StandardError
          {}
        end
      end

      def size_for(path)
        return 0 unless path

        File.size(path)
      rescue StandardError
        0
      end

      def clear_metadata_cache
        @metadata_cache.clear
      end

      private

      def index_recent_by_path
        items = Adapters::Storage::RecentFiles.load
        Array(items).each_with_object({}) do |recent_item, acc|
          path = recent_item['path'] || recent_item[:path]
          accessed = recent_item['accessed'] || recent_item[:accessed]
          acc[path] = accessed if path && accessed
        end
      end
    end
  end
end
