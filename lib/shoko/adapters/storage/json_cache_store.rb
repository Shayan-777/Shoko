# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'securerandom'

require_relative 'atomic_file_writer'
require_relative 'cache_paths'
require_relative 'json_cache_layout_store'
require_relative 'json_cache_manifest_store'
require 'shoko/adapters/storage/source_fingerprint'
require 'shoko/shared/hash_normalizer'
require 'shoko/shared/resilient_diagnostics'

module Shoko
  module Adapters
    module Storage
      # JSON-backed cache store for EPUB payloads + layouts.
      #
      # This store persists only primitive JSON data and keeps binary resources
      # as separate blobs on disk (referenced from the JSON payload).
      class JsonCacheStore
        ENGINE = 'json'
        FORMAT = 'shoko-cache-payload'
        FORMAT_VERSION = 2
        CHAPTERS_FORMAT_VERSION = 2

        # Raw payload read from disk (metadata + chapter/resource indexes + layouts).
        Payload = Struct.new(:metadata_row, :chapters, :resources, :layouts)

        MANIFEST_FILENAME = JsonCacheManifestStore::FILENAME
        MANIFEST_LOCK_FILENAME = JsonCacheManifestStore::LOCK_FILENAME

        SHA256_HEX_PATTERN = /\A[0-9a-f]{64}\z/i

        CHAPTERS_DIRNAME = 'chapters'
        CHAPTERS_RAW_DIRNAME = 'raw'
        CHAPTERS_GENERATION_BYTES = 8
        CHAPTERS_GENERATION_PATTERN = /\A[0-9a-f]{16}\z/i
        CHAPTER_FILENAME_DIGITS = 6
        MAX_CHAPTER_COUNT = 20_000
        CHAPTER_ROW_EXCLUDED_KEYS = %w[raw_content lines_json blocks_json].freeze

        class << self
          def with_manifest_rows_cache(enabled:, &)
            JsonCacheManifestStore.with_cache(enabled: enabled, &)
          end

          def manifest_rows_cache_enabled?(runtime_config: nil)
            JsonCacheManifestStore.cache_enabled?(runtime_config: runtime_config)
          end

          def clear_manifest_rows_cache(cache_root = nil)
            JsonCacheManifestStore.clear_cache(cache_root)
          end

          def manifest_rows(cache_root, runtime_config: nil)
            JsonCacheManifestStore.rows(cache_root, runtime_config: runtime_config)
          end
        end

        def initialize(cache_root: CachePaths.cache_root, logger: nil, runtime_config: nil)
          @cache_root = cache_root
          @logger = logger
          @runtime_config = runtime_config
          @layout_store = JsonCacheLayoutStore.new(cache_root: @cache_root, logger: @logger)
          @manifest_store = JsonCacheManifestStore.new(cache_root: @cache_root, logger: @logger)
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
        # resilient-boundary
        rescue StandardError => e
          record_cache_error('fetch failed', e, sha: sha.to_s)
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
        # resilient-boundary
        rescue StandardError => e
          record_cache_error('write failed', e, sha: sha.to_s)
          cleanup_failed_chapter_generation(normalized_sha, chapter_generation) if normalized_sha && chapter_generation
          false
        end

        def load_layout(sha, key)
          @layout_store.load(sha, key)
        end

        def fetch_layouts(sha)
          @layout_store.fetch(sha)
        end

        def chapters_complete?(sha, generation, expected_count:)
          normalized_sha = normalize_sha!(sha)
          gen = normalize_chapter_generation(generation)
          count = normalize_expected_chapter_count(expected_count)
          return false unless gen && count
          return true if count.zero?

          chapter_files_complete?(normalized_sha, gen, count)
        # resilient-boundary
        rescue StandardError => e
          record_cache_error('chapters completeness check failed', e,
                             sha: sha.to_s, generation: generation.to_s, expected: expected_count.to_i)
          false
        end

        def mutate_layouts(sha, &)
          @layout_store.mutate(sha, &)
        end

        def delete_payload(sha)
          normalized_sha = normalize_sha!(sha)
          FileUtils.rm_f(payload_path(normalized_sha))
          @layout_store.delete(normalized_sha)
          FileUtils.rm_rf(resources_dir(normalized_sha))
          FileUtils.rm_rf(chapters_dir(normalized_sha))
          remove_from_manifest(normalized_sha)
          true
        # resilient-boundary
        rescue StandardError => e
          record_cache_error('delete failed', e, sha: sha.to_s)
          false
        end

        def list_books
          self.class.manifest_rows(@cache_root, runtime_config: @runtime_config)
        end

        private

        # Cache reads and writes are best-effort: a corrupt cache file, a
        # partial write, or a transient filesystem error must degrade to
        # "no cache" rather than crash the reader. The errors raised at these
        # sites (JSON::ParserError, Errno::*, plain bugs) are not Shoko::Error,
        # so the boundary is StandardError (constitution section 5). Returns
        # nil so single-value callers can `record_cache_error(...)` directly.
        def record_cache_error(operation, error, **context)
          Shoko::Shared::ResilientDiagnostics.debug(
            @logger, "JsonCacheStore: #{operation}",
            **context, error_class: error.class.name, error: error.message
          )
          nil
        end

        # --- Payload IO + normalization ---

        def payload_path(sha)
          File.join(@cache_root, "#{normalize_sha!(sha)}.json")
        end

        def load_payload_data(sha)
          path = payload_path(sha)
          return nil unless File.file?(path)

          data = JSON.parse(File.read(path))
          valid_payload_file?(data) ? data : nil
        end

        def valid_payload_file?(data)
          return false unless data.is_a?(Hash)
          return false unless payload_header_valid?(data)

          metadata_row = data['metadata_row']
          return false unless metadata_row.is_a?(Hash)
          return false unless payload_metadata_valid?(metadata_row)
          return false unless payload_collections_valid?(data)

          true
        end

        def payload_header_valid?(data)
          data['format'] == FORMAT &&
            data['format_version'].to_i == FORMAT_VERSION &&
            data['engine'].to_s == ENGINE
        end

        def payload_metadata_valid?(metadata_row)
          CHAPTERS_GENERATION_PATTERN.match?(metadata_row['chapters_generation'].to_s) &&
            metadata_row['chapters_format_version'].to_i == CHAPTERS_FORMAT_VERSION
        end

        def payload_collections_valid?(data)
          data['chapters'].is_a?(Array) && data['resources'].is_a?(Array)
        end

        def build_metadata_row(serialized_book, normalized_sha, source_path:, source_mtime:, generated_at:)
          now = Time.now.utc.to_f
          stringify_keys(serialized_book).merge(
            'source_sha' => normalized_sha,
            'source_path' => source_path,
            'source_mtime' => source_mtime&.to_f,
            'source_size_bytes' => safe_file_size(source_path),
            'source_fingerprint' => Shoko::Adapters::Storage::SourceFingerprint.compute(source_path),
            'generated_at' => generated_at&.to_f,
            'created_at' => now,
            'updated_at' => now,
            'engine' => ENGINE
          )
        end

        def payload_hash(metadata_row, chapter_generation, indexes)
          chapters_index = indexes.fetch(:chapters)
          resources_index = indexes.fetch(:resources)
          metadata_row['chapters_generation'] = chapter_generation
          metadata_row['chapters_format_version'] = CHAPTERS_FORMAT_VERSION

          {
            'format' => FORMAT,
            'format_version' => FORMAT_VERSION,
            'engine' => ENGINE,
            'metadata_row' => metadata_row,
            'chapters' => chapters_index,
            'resources' => resources_index,
          }
        end

        def write_payload_file(sha, payload)
          AtomicFileWriter.write(payload_path(sha), JSON.generate(payload))
        end

        def post_write_housekeeping(sha, metadata_row, chapter_generation, cache_size_bytes, serialized_layouts:)
          @layout_store.write(sha, serialized_layouts)
          update_manifest(metadata_row, cache_size_bytes: cache_size_bytes)
          cleanup_old_chapter_generations(sha, keep: chapter_generation)
        end

        def stringify_keys(hash)
          (hash || {}).transform_keys(&:to_s)
        rescue NoMethodError, TypeError
          hash || {}
        end

        def normalize_sha!(sha)
          value = sha.to_s.strip
          raise ArgumentError, 'sha is blank' if value.empty?
          raise ArgumentError, 'sha must be a 64-char hex digest' unless SHA256_HEX_PATTERN.match?(value)

          value.downcase
        end

        def safe_file_size(path)
          return nil if path.nil? || path.to_s.empty?

          File.size(path)
        end

        # --- Chapter persistence ---

        def chapters_dir(sha)
          File.join(@cache_root, CHAPTERS_DIRNAME, normalize_sha!(sha))
        end

        def chapter_generation_dir(sha, generation)
          gen = generation.to_s.strip
          raise ArgumentError, 'chapter generation is invalid' unless CHAPTERS_GENERATION_PATTERN.match?(gen)

          File.join(chapters_dir(sha), gen.downcase)
        end

        def chapter_raw_dir(sha, generation)
          File.join(chapter_generation_dir(sha, generation), CHAPTERS_RAW_DIRNAME)
        end

        def chapter_raw_file(sha, generation, position)
          idx = Integer(position)
          raise ArgumentError, 'chapter position must be >= 0' if idx.negative?

          name = format("%0#{CHAPTER_FILENAME_DIGITS}d.xhtml", idx)
          File.join(chapter_raw_dir(sha, generation), name)
        end

        def normalize_chapter_generation(generation)
          gen = generation.to_s.strip.downcase
          CHAPTERS_GENERATION_PATTERN.match?(gen) ? gen : nil
        end

        def normalize_expected_chapter_count(expected_count)
          count = expected_count.to_i
          return nil if count.negative?
          return nil if count > MAX_CHAPTER_COUNT

          count
        end

        def chapter_files_complete?(sha, generation, expected_count)
          raw_dir = chapter_raw_dir(sha, generation)
          return false unless Dir.exist?(raw_dir)

          expected_count.times do |idx|
            return false unless File.file?(chapter_raw_file(sha, generation, idx))
          end
          true
        end

        def persist_chapters(sha, chapter_rows)
          chapter_rows = Array(chapter_rows)
          generation = new_chapter_generation
          return [[], generation, 0] if chapter_rows.empty?

          FileUtils.mkdir_p(chapter_raw_dir(sha, generation))
          rows, total_bytes = persist_chapter_rows(sha, generation, chapter_rows)
          [rows, generation, total_bytes]
        end

        def new_chapter_generation
          SecureRandom.hex(CHAPTERS_GENERATION_BYTES)
        end

        def persist_chapter_rows(sha, generation, chapter_rows)
          rows = []
          total_bytes = 0
          chapter_rows.each do |row|
            filtered, bytesize = persist_chapter_row(sha, generation, row)
            rows << filtered
            total_bytes += bytesize
          end
          [rows, total_bytes]
        end

        def persist_chapter_row(sha, generation, row)
          idx = chapter_row_index(row)
          text = chapter_row_raw_content(row).to_s
          AtomicFileWriter.write(chapter_raw_file(sha, generation, idx), text)
          [filtered_chapter_index_row(row, idx), text.bytesize]
        end

        def chapter_row_index(row)
          normalized = normalized_row(row)
          raise ArgumentError, 'chapter row must be a Hash' unless normalized

          position = normalized[:position]
          idx = Integer(position)
          raise ArgumentError, 'chapter position must be >= 0' if idx.negative?

          idx
        end

        def chapter_row_raw_content(row)
          normalized = normalized_row(row)
          normalized ? normalized[:raw_content] : nil
        end

        def filtered_chapter_index_row(row, idx)
          filtered = {}
          row.each do |key, value|
            key_str = key.to_s
            next if CHAPTER_ROW_EXCLUDED_KEYS.include?(key_str)

            filtered[key_str] = value
          end
          filtered['position'] = idx
          filtered
        end

        def cleanup_old_chapter_generations(sha, keep:)
          base = chapters_dir(sha)
          return unless Dir.exist?(base)

          keep_name = keep.to_s.strip.downcase
          Dir.children(base).each do |entry|
            next if entry == keep_name

            path = File.join(base, entry)
            next unless File.directory?(path)
            next unless CHAPTERS_GENERATION_PATTERN.match?(entry)

            FileUtils.rm_rf(path)
          end
        end

        def cleanup_failed_chapter_generation(sha, generation)
          path = chapter_generation_dir(sha, generation)
          FileUtils.rm_rf(path)
        end

        def normalized_row(row)
          Shoko::Shared::HashNormalizer.symbolize_keys(row)
        end

        # --- Resource persistence ---

        def resources_dir(sha)
          File.join(@cache_root, 'resources', normalize_sha!(sha))
        end

        def resource_blob_path(sha, blob_key)
          File.join(resources_dir(sha), "#{blob_key}.bin")
        end

        def hydrate_resources(sha, index_rows)
          Array(index_rows).filter_map { |row| hydrate_resource_row(sha, row) }
        end

        def hydrate_resource_row(sha, row)
          path, blob_key = resource_index_row_fields(row)
          path_string = path.to_s
          blob_key_string = blob_key.to_s
          return nil if path_string.empty? || blob_key_string.empty?

          data = File.binread(resource_blob_path(sha, blob_key_string))
          data.force_encoding(Encoding::BINARY)
          { path: path_string, data: data }
        end

        def resource_index_row_fields(row)
          normalized = Shoko::Shared::HashNormalizer.symbolize_keys(row) || {}
          [normalized[:path], normalized[:blob]]
        end

        def persist_resources(sha, resources_rows)
          resources_rows = Array(resources_rows)
          return [[], 0] if resources_rows.empty?

          FileUtils.mkdir_p(resources_dir(sha))

          rows = []
          total_bytes = 0
          resources_rows.each do |row|
            persisted = persist_resource_row(sha, row)
            next unless persisted

            rows << persisted[:index_row]
            total_bytes += persisted[:bytesize]
          end

          [rows, total_bytes]
        end

        def persist_resource_row(sha, row)
          path, data = resource_row_fields(row)
          path_string = path.to_s
          return nil if path_string.empty?

          bytes = String(data).dup
          bytes.force_encoding(Encoding::BINARY)
          blob_key = Digest::SHA256.hexdigest(path_string)

          AtomicFileWriter.write(resource_blob_path(sha, blob_key), bytes, binary: true)

          bytesize = bytes.bytesize
          {
            bytesize: bytesize,
            index_row: { 'path' => path_string, 'blob' => blob_key, 'bytesize' => bytesize },
          }
        end

        def resource_row_fields(row)
          normalized = Shoko::Shared::HashNormalizer.symbolize_keys(row) || {}
          [normalized[:path], normalized[:data]]
        end

        # --- Manifest (cache listing) ---

        def update_manifest(metadata_row, cache_size_bytes:)
          @manifest_store.update(metadata_row, cache_size_bytes: cache_size_bytes)
        end

        def remove_from_manifest(sha)
          @manifest_store.remove(sha)
        end
      end
    end
  end
end
