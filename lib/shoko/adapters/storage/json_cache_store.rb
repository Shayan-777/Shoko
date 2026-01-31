# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'securerandom'

require_relative 'atomic_file_writer'
require_relative 'cache_paths'
require_relative '../book_sources/source_fingerprint'

module Shoko
  module Adapters::Storage
    # JSON-backed cache store for EPUB payloads + layouts.
    #
    # This store persists only primitive JSON data and keeps binary resources
    # as separate blobs on disk (referenced from the JSON payload).
    class JsonCacheStore
      ENGINE = 'json'
      FORMAT = 'shoko-cache-payload'
      FORMAT_VERSION = 2

      # Raw payload read from disk (metadata + chapter/resource indexes + layouts).
      Payload = Struct.new(:metadata_row, :chapters, :resources, :layouts, keyword_init: true)

      MANIFEST_FILENAME = 'cache_manifest.json'

      SHA256_HEX_PATTERN = /\A[0-9a-f]{64}\z/i

      MAX_LAYOUT_KEY_BYTES = 200
      LAYOUT_KEY_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/

      CHAPTERS_DIRNAME = 'chapters'
      CHAPTERS_RAW_DIRNAME = 'raw'
      CHAPTERS_GENERATION_BYTES = 8
      CHAPTERS_GENERATION_PATTERN = /\A[0-9a-f]{16}\z/i
      CHAPTER_FILENAME_DIGITS = 6
      MAX_CHAPTER_COUNT = 20_000

      def initialize(cache_root: CachePaths.cache_root, logger: nil)
        @cache_root = cache_root
        @logger = logger
        FileUtils.mkdir_p(@cache_root)
      end

      def engine
        ENGINE
      end

      def fetch_payload(sha, include_resources: false)
        data = load_payload_data(sha)
        return nil unless data

        Payload.new(
          metadata_row: data.fetch('metadata_row', {}),
          chapters: data.fetch('chapters', []),
          resources: include_resources ? hydrate_resources(sha, data.fetch('resources', [])) : [],
          layouts: fetch_layouts(sha)
        )
      rescue StandardError => e
        @logger&.debug('JsonCacheStore: fetch failed', sha: sha.to_s, error: e.message)
        nil
      end

      def write_payload(sha:, source_path:, source_mtime:, generated_at:, serialized_book:, serialized_chapters:,
                        serialized_resources:, serialized_layouts:)
        normalized_sha = normalize_sha!(sha)

        metadata_row = build_metadata_row(serialized_book, normalized_sha, source_path:, source_mtime:, generated_at:)
        chapters_index, chapter_generation, chapter_bytes = persist_chapters(normalized_sha, serialized_chapters)
        resources_index, resource_bytes = persist_resources(normalized_sha, serialized_resources)
        size_bytes = chapter_bytes.to_i + resource_bytes.to_i
        indexes = { chapters: chapters_index, resources: resources_index }
        payload = payload_hash(metadata_row, chapter_generation, indexes)
        write_payload_file(normalized_sha, payload)
        post_write_housekeeping(normalized_sha, metadata_row, chapter_generation, size_bytes, serialized_layouts:)
        true
      rescue StandardError => e
        @logger&.debug('JsonCacheStore: write failed', sha: sha.to_s, error: e.message)
        cleanup_failed_chapter_generation(normalized_sha, chapter_generation) if normalized_sha && chapter_generation
        false
      end

      def load_layout(sha, key)
        file = layout_file(sha, key)
        return nil unless File.file?(file)

        JSON.parse(File.read(file))
      rescue StandardError => e
        @logger&.debug('JsonCacheStore: layout load failed', sha: sha.to_s, key: key.to_s,
                                                                                        error: e.message)
        nil
      end

      def fetch_layouts(sha)
        dir = layouts_dir(sha)
        return {} unless Dir.exist?(dir)

        Dir.children(dir).each_with_object({}) do |entry, layouts|
          key = layout_key_for_entry(entry)
          next unless key

          payload = read_layout_payload(dir, entry, sha: sha, key: key)
          layouts[key] = payload if payload
        end
      rescue StandardError => e
        @logger&.debug('JsonCacheStore: layouts fetch failed', sha: sha.to_s,
                                                                                          error: e.message)
        {}
      end

      def chapters_complete?(sha, generation, expected_count:)
        normalized_sha = normalize_sha!(sha)
        gen = normalize_chapter_generation(generation)
        count = normalize_expected_chapter_count(expected_count)
        return false unless gen && count
        return true if count.zero?

        chapter_files_complete?(normalized_sha, gen, count)
      rescue StandardError => e
        @logger&.debug('JsonCacheStore: chapters completeness check failed',
                                                  sha: sha.to_s, generation: generation.to_s, expected: expected_count.to_i,
                                                  error: e.message)
        false
      end

      def mutate_layouts(sha)
        layouts = fetch_layouts(sha)
        yield layouts
        write_layouts(sha, layouts)
        true
      rescue StandardError => e
        @logger&.debug('JsonCacheStore: mutate layouts failed', sha: sha.to_s,
                                                                                           error: e.message)
        false
      end

      def delete_payload(sha)
        normalized_sha = normalize_sha!(sha)
        FileUtils.rm_f(payload_path(normalized_sha))
        FileUtils.rm_rf(layouts_dir(normalized_sha))
        FileUtils.rm_rf(resources_dir(normalized_sha))
        FileUtils.rm_rf(chapters_dir(normalized_sha))
        remove_from_manifest(normalized_sha)
        true
      rescue StandardError => e
        @logger&.debug('JsonCacheStore: delete failed', sha: sha.to_s, error: e.message)
        false
      end

      def list_books
        self.class.manifest_rows(@cache_root)
      rescue StandardError
        []
      end

      def self.manifest_rows(cache_root)
        read_manifest_file(File.join(cache_root, MANIFEST_FILENAME))
      rescue StandardError
        []
      end
    end
  end
end

require_relative 'json_cache_store/payload_helpers'
require_relative 'json_cache_store/chapters'
require_relative 'json_cache_store/layouts'
require_relative 'json_cache_store/resources'
require_relative 'json_cache_store/manifest'
