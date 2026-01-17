# frozen_string_literal: true

require 'json'
require 'time'

require_relative '../cache_paths'
require_relative '../json_cache_store'
require_relative '../cache_pointer_manager'
require_relative '../epub_cache'
require_relative '../../output/terminal/terminal_sanitizer'

module Shoko
  module Adapters::Storage::Repositories
    # Provides read-only access to cached library metadata on disk.
    class CachedLibraryRepository
      def initialize(cache_root: Adapters::Storage::CachePaths.cache_root, store: nil)
        @cache_root = cache_root
        @cache_store = store || Adapters::Storage::JsonCacheStore.new(cache_root:)
      end

      def list_entries
        rows = fetch_manifest_rows
        rows = fetch_rows if rows.empty?
        return [] if rows.empty?

        rows.filter_map { |row| build_entry_from_row(row) }
      end

      private

      def fetch_rows
        @cache_store.list_books
      end

      def fetch_manifest_rows
        Adapters::Storage::JsonCacheStore.manifest_rows(@cache_root)
      end

      def build_entry_from_row(row)
        sha = row.is_a?(Hash) ? (row['source_sha'] || row[:source_sha]) : nil
        pointer_path = Adapters::Storage::EpubCache.cache_path_for_sha(sha, cache_root: @cache_root)
        return nil unless pointer_path

        ensure_pointer_file(row, pointer_path)

        metadata = parse_json_object(row['metadata_json'])
        authors = parse_json_array(row['authors_json']).map { |name| sanitize_display(name.to_s) }

        {
          title: sanitize_display(present_or_default(row['title'], 'Unknown')),
          authors: authors.join(', '),
          year: extract_year(metadata),
          size_bytes: (row['cache_size_bytes'] || safe_file_size(pointer_path)).to_i,
          open_path: pointer_path,
          epub_path: row['source_path'].to_s,
        }
      end

      def ensure_pointer_file(row, path)
        return path if File.exist?(path) || row['source_sha'].to_s.empty?

        generated_at = begin
          raw = row['generated_at']
          raw ? Time.at(raw.to_f).utc.iso8601 : Time.now.utc.iso8601
        rescue StandardError
          Time.now.utc.iso8601
        end

        metadata = {
          'format' => Adapters::Storage::CachePointerManager::POINTER_FORMAT,
          'version' => Adapters::Storage::CachePointerManager::POINTER_VERSION,
          'sha256' => row['source_sha'],
          'source_path' => row['source_path'],
          'generated_at' => generated_at,
          'engine' => Adapters::Storage::JsonCacheStore::ENGINE,
        }

        Adapters::Storage::CachePointerManager.new(path).write(metadata)
        path
      rescue StandardError
        path
      end

      def parse_json_object(value)
        return {} unless value
        return value if value.is_a?(Hash)

        parsed = JSON.parse(value)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError, TypeError
        {}
      end

      def parse_json_array(value)
        return [] unless value
        return value if value.is_a?(Array)

        parsed = JSON.parse(value)
        parsed.is_a?(Array) ? parsed : []
      rescue JSON::ParserError, TypeError
        []
      end

      def extract_year(metadata)
        return '' unless metadata.respond_to?(:[])

        year = metadata['year'] || metadata[:year]
        year ? year.to_s : ''
      end

      def present_or_default(value, fallback)
        str = value.to_s.strip
        str.empty? ? fallback : value
      end

      def safe_file_size(path)
        File.size(path)
      rescue StandardError
        0
      end

      def sanitize_display(text)
        Shoko::Adapters::Output::Terminal::TerminalSanitizer.sanitize(text.to_s, preserve_newlines: false,
                                                                                 preserve_tabs: false)
      rescue StandardError
        text.to_s
      end
    end
  end
end
