# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'securerandom'

require_relative 'atomic_file_writer'
require_relative 'cache_paths'
require_relative '../../shared/source_fingerprint'
require 'shoko/shared/hash_normalizer'

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

        MANIFEST_FILENAME = 'cache_manifest.json'
        MANIFEST_LOCK_FILENAME = 'cache_manifest.lock'
        MANIFEST_ROWS_CACHE_ENABLED_KEY = :shoko_manifest_rows_cache_enabled

        SHA256_HEX_PATTERN = /\A[0-9a-f]{64}\z/i

        MAX_LAYOUT_KEY_BYTES = 200
        LAYOUT_KEY_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/

        CHAPTERS_DIRNAME = 'chapters'
        CHAPTERS_RAW_DIRNAME = 'raw'
        CHAPTERS_GENERATION_BYTES = 8
        CHAPTERS_GENERATION_PATTERN = /\A[0-9a-f]{16}\z/i
        CHAPTER_FILENAME_DIGITS = 6
        MAX_CHAPTER_COUNT = 20_000
        CHAPTER_ROW_EXCLUDED_KEYS = %w[raw_content lines_json blocks_json].freeze

        # Initialized eagerly at load: a lazy `||=` here would itself race the
        # first two threads that touch the rows cache.
        @manifest_rows_cache_mutex = Mutex.new
        @manifest_rows_cache_data = {}

        class << self
          def with_manifest_rows_cache(enabled:)
            previous = Thread.current[MANIFEST_ROWS_CACHE_ENABLED_KEY]
            Thread.current[MANIFEST_ROWS_CACHE_ENABLED_KEY] = enabled ? true : false
            yield
          ensure
            Thread.current[MANIFEST_ROWS_CACHE_ENABLED_KEY] = previous
          end

          def manifest_rows_cache_enabled?(runtime_config: nil)
            override = Thread.current[MANIFEST_ROWS_CACHE_ENABLED_KEY]
            return override unless override.nil?
            return true if runtime_config.nil?

            !runtime_config.manifest_rows_cache_disabled?
          end

          def clear_manifest_rows_cache(cache_root = nil)
            manifest_rows_cache_mutex.synchronize do
              if cache_root
                manifest_rows_cache_data.delete(manifest_cache_key(cache_root))
              else
                manifest_rows_cache_data.clear
              end
            end
          end

          def manifest_rows(cache_root, runtime_config: nil)
            path = File.join(cache_root, MANIFEST_FILENAME)
            return [] unless File.file?(path)

            if manifest_rows_cache_enabled?(runtime_config: runtime_config)
              cached = fetch_cached_manifest_rows(cache_root, path)
              return cached unless cached.nil?
            end

            rows = normalize_manifest_rows(read_manifest_file(path))
            cache_manifest_rows(cache_root, path, rows) if manifest_rows_cache_enabled?(runtime_config: runtime_config)
            clone_manifest_rows(rows)
          end

          private

          def read_manifest_file(path)
            return [] unless File.file?(path)

            data = JSON.parse(File.read(path))
            data.is_a?(Array) ? data : []
          rescue JSON::ParserError, SystemCallError, IOError => e
            discard_corrupt_manifest(e)
          end

          # A corrupt or unreadable manifest reads as empty so a damaged cache
          # never crashes the library listing. The realizable failures here are
          # bounded (parse + filesystem), so this stays a narrow rescue.
          def discard_corrupt_manifest(_error)
            []
          end

          def fetch_cached_manifest_rows(cache_root, path)
            stat = File.stat(path)
            entry = nil
            manifest_rows_cache_mutex.synchronize do
              entry = manifest_rows_cache_data[manifest_cache_key(cache_root)]
            end
            return nil unless entry
            return nil unless matching_manifest_cache_entry?(entry, stat)

            clone_manifest_rows(entry[:rows])
          end

          def cache_manifest_rows(cache_root, path, rows)
            stat = File.stat(path)
            normalized = normalize_manifest_rows(rows)
            key = manifest_cache_key(cache_root)
            manifest_rows_cache_mutex.synchronize do
              manifest_rows_cache_data[key] = { mtime: stat.mtime.to_f, size: stat.size, rows: normalized }
            end
          end

          def normalize_manifest_rows(rows)
            Array(rows).each_with_object([]) do |row, acc|
              acc << row.dup if row.is_a?(Hash)
            end
          end

          def clone_manifest_rows(rows)
            rows.map(&:dup)
          end

          def matching_manifest_cache_entry?(entry, stat)
            cached_mtime = entry[:mtime].to_f
            stat_mtime = stat.mtime.to_f

            (cached_mtime - stat_mtime).abs < Float::EPSILON && entry[:size] == stat.size
          end

          attr_reader :manifest_rows_cache_mutex, :manifest_rows_cache_data

          def manifest_cache_key(cache_root)
            File.expand_path(cache_root.to_s)
          end
        end

        def initialize(cache_root: CachePaths.cache_root, logger: nil, runtime_config: nil)
          @cache_root = cache_root
          @logger = logger
          @runtime_config = runtime_config
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
          file = layout_file(sha, key)
          return nil unless File.file?(file)

          JSON.parse(File.read(file))
        # resilient-boundary
        rescue StandardError => e
          record_cache_error('layout load failed', e, sha: sha.to_s, key: key.to_s)
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
        # resilient-boundary
        rescue StandardError => e
          record_cache_error('layouts fetch failed', e, sha: sha.to_s)
          {}
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

        def mutate_layouts(sha)
          layouts = fetch_layouts(sha)
          yield layouts
          write_layouts(sha, layouts)
          true
        # resilient-boundary
        rescue StandardError => e
          record_cache_error('mutate layouts failed', e, sha: sha.to_s)
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
        # so the boundary is StandardError (constitution §VIII / R4). Returns
        # nil so single-value callers can `record_cache_error(...)` directly.
        def record_cache_error(operation, error, **context)
          @logger&.debug("JsonCacheStore: #{operation}",
                         **context, error_class: error.class.name, error: error.message)
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
            'source_fingerprint' => Shoko::Shared::SourceFingerprint.compute(source_path),
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
          write_layouts(sha, serialized_layouts)
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

        # --- Layout storage ---

        def layouts_dir(sha)
          File.join(@cache_root, 'layouts', normalize_sha!(sha))
        end

        def layout_file(sha, key)
          File.join(layouts_dir(sha), "#{normalize_layout_key!(key)}.json")
        end

        def layout_key_for_entry(entry)
          return nil unless entry.end_with?('.json')

          key = entry.delete_suffix('.json')
          layout_key_valid?(key) ? key : nil
        end

        def read_layout_payload(dir, entry, sha:, key:)
          JSON.parse(File.read(File.join(dir, entry)))
        # resilient-boundary
        rescue StandardError => e
          record_cache_error('layout parse failed', e, sha: sha.to_s, key: key.to_s)
        end

        def write_layouts(sha, layouts_hash)
          dir = layouts_dir(sha)
          FileUtils.mkdir_p(dir)
          existing = Dir.exist?(dir) ? Dir.children(dir).select { |entry| entry.end_with?('.json') } : []

          written = []
          layouts_hash.each do |key, payload|
            normalized_key = normalize_layout_key!(key)
            file = File.join(dir, "#{normalized_key}.json")
            AtomicFileWriter.write(file, JSON.generate(payload))
            written << "#{normalized_key}.json"
          end

          stale = existing - written
          stale.each { |entry| FileUtils.rm_f(File.join(dir, entry)) }
        end

        def layout_key_valid?(key)
          normalize_layout_key!(key)
          true
        end

        def normalize_layout_key!(key)
          value = key.to_s
          raise ArgumentError, 'layout key is blank' if value.empty?
          raise ArgumentError, 'layout key too long' if value.bytesize > MAX_LAYOUT_KEY_BYTES
          raise ArgumentError, 'layout key contains null byte' if value.include?("\0")
          raise ArgumentError, 'layout key contains path separator' if value.include?('/') || value.include?('\\')
          raise ArgumentError, 'layout key has invalid characters' unless LAYOUT_KEY_PATTERN.match?(value)

          value
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

        def manifest_path
          File.join(@cache_root, MANIFEST_FILENAME)
        end

        def manifest_lock_path
          File.join(@cache_root, MANIFEST_LOCK_FILENAME)
        end

        def update_manifest(metadata_row, cache_size_bytes:)
          row = metadata_row.merge('cache_size_bytes' => cache_size_bytes.to_i)
          with_manifest_lock do
            manifest = fresh_manifest_rows
            manifest.reject! { |entry| entry['source_sha'] == row['source_sha'] }
            manifest << row
            AtomicFileWriter.write(manifest_path, JSON.generate(manifest))
          end
          self.class.clear_manifest_rows_cache(@cache_root)
        # resilient-boundary
        rescue StandardError => e
          record_cache_error('manifest write failed', e)
        end

        def remove_from_manifest(sha)
          with_manifest_lock do
            manifest = fresh_manifest_rows
            manifest.reject! { |entry| entry['source_sha'] == sha }
            AtomicFileWriter.write(manifest_path, JSON.generate(manifest))
          end
          self.class.clear_manifest_rows_cache(@cache_root)
        end

        # Serializes the manifest read-modify-write across threads AND
        # processes — the prepagination child batch and the parent app can
        # both be importing books. The lock is a sidecar file because the
        # manifest itself is replaced by rename on every write; a lock on the
        # replaced inode would guard nothing.
        def with_manifest_lock
          FileUtils.mkdir_p(@cache_root)
          File.open(manifest_lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
            lock.flock(File::LOCK_EX)
            yield
          end
        end

        # Reads the manifest directly from disk: inside the write lock the
        # row set must reflect the very latest concurrent write, so the
        # mtime-keyed rows cache (whose timestamp equality cannot distinguish
        # two writes in the same instant) is bypassed.
        def fresh_manifest_rows
          return [] unless File.file?(manifest_path)

          data = JSON.parse(File.read(manifest_path))
          data.is_a?(Array) ? data.grep(Hash) : []
        rescue JSON::ParserError, SystemCallError, IOError => e
          discard_corrupt_manifest_rows(e)
        end

        # A corrupt manifest reads as empty inside the lock for the same
        # reason the class-side reader degrades: a damaged cache must never
        # block imports from repairing it with the next write.
        def discard_corrupt_manifest_rows(_error)
          []
        end
      end
    end
  end
end
