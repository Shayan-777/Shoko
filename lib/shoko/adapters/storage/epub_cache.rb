# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'time'

require_relative '../../core/models/book_data'
require_relative '../../core/models/chapter'
require_relative '../../core/models/toc_entry'
require_relative '../../core/models/content_block'
require_relative '../../shared/errors'
require_relative '../../shared/text_sanitizer'
require_relative 'cache_paths'
require_relative 'json_cache_store'
require_relative 'cache_pointer_manager'
require_relative 'lazy_file_string'

module Shoko
  module Adapters
    module Storage
      # JSON-backed cache for imported EPUB data and derived pagination layouts.
      # Pointer files keep lightweight `.cache` discovery while the bulk payload
      # lives in JSON + binary blobs.
      class EpubCache
        CACHE_VERSION   = 8
        CACHE_EXTENSION = '.cache'
        SHA256_HEX_PATTERN = /\A[0-9a-f]{64}\z/i

        # Immutable representation of the persisted cache payload.
        CachePayload = Struct.new(
          :version,
          :source_sha256,
          :source_path,
          :source_mtime,
          :generated_at,
          :book,
          :layouts
        )

        class << self
          def cache_extension = CACHE_EXTENSION

          def cache_file?(path)
            File.file?(path) && File.extname(path).casecmp(CACHE_EXTENSION).zero?
          end

          def cache_path_for_sha(sha, cache_root: CachePaths.cache_root)
            normalized = sha.to_s.strip
            return nil unless normalized.match?(SHA256_HEX_PATTERN)

            File.join(cache_root, "#{normalized.downcase}#{CACHE_EXTENSION}")
          end
        end

        attr_reader :cache_path, :source_path

        def initialize(path, cache_root: CachePaths.cache_root, store: nil, logger: nil, runtime_config: nil)
          @cache_root = cache_root
          @logger = logger
          @runtime_config = runtime_config
          @cache_store = store || JsonCacheStore.new(
            cache_root: @cache_root,
            logger: @logger,
            runtime_config: @runtime_config
          )
          @raw_path = File.expand_path(path)
          @payload_cache = nil
          @layout_cache = {}
          @pointer_metadata = nil
          setup_source_reference
        end

        # Load pointer payload without validating source. Used by cached-library
        # direct opens.
        def read_cache(strict: false)
          payload = load_payload
          return nil unless payload

          return payload unless strict

          payload_valid?(payload) ? payload : invalidate_and_nil
        end

        # Load payload and ensure it matches the original EPUB file.
        def load_for_source(strict: false)
          payload = load_payload
          return nil unless payload

          if payload_valid?(payload) && payload_matches_source?(payload, strict:)
            payload
          else
            invalidate_and_nil
          end
        end

        def write_book!(book_data)
          ensure_sha!
          return nil unless persist_payload(book_data, layouts_hash: {})

          @layout_cache = {}
          @payload_cache = load_payload_from_store(@source_sha)
        rescue Shoko::Error => e
          @logger&.debug('EpubCache: failed to write cache', path: @cache_path, error: e.message)
          nil
        end

        def load_layout(key)
          key_str = key.to_s
          return deep_dup(@layout_cache[key_str]) if @layout_cache.key?(key_str)

          payload = @cache_store.load_layout(@source_sha, key_str)
          return nil unless payload

          cache_layout!(key_str, payload)
          deep_dup(payload)
        end

        def mutate_layouts!
          ensure_sha!
          updated_layouts = nil
          success = @cache_store.mutate_layouts(@source_sha) do |layouts|
            yield layouts
            updated_layouts = layouts
          end
          update_layout_cache_from_layouts(updated_layouts) if success
          success
        rescue Shoko::Error => e
          @logger&.debug('EpubCache: failed to update layouts', path: @cache_path, error: e.message)
          false
        end

        def invalidate!
          ensure_sha!
          @cache_store.delete_payload(@source_sha) if @source_sha
          FileUtils.rm_f(@cache_path) if @cache_path && File.exist?(@cache_path)
        ensure
          @payload_cache = nil
          @layout_cache = {}
          @pointer_metadata = nil
        end

        def cache_file?
          @source_type == :cache_pointer
        end

        def sha256
          ensure_sha!
          @source_sha
        end

        def layout_keys
          ensure_sha!
          keys = @cache_store.fetch_layouts(@source_sha).keys
          keys |= @layout_cache.keys
          keys
        end

        def chapters_complete?(expected_count, generation: nil)
          ensure_sha!
          gen = generation
          gen ||= @payload_cache&.book&.chapters_generation
          return false if gen.to_s.strip.empty?

          @cache_store.chapters_complete?(@source_sha, gen, expected_count: expected_count)
        end

        private

        # --- Source resolution (EPUB source vs `.cache` pointer file) ---

        def setup_source_reference
          if self.class.cache_file?(@raw_path)
            setup_source_reference_from_pointer
          else
            setup_source_reference_from_epub
          end
        end

        def setup_source_reference_from_pointer
          @cache_path = @raw_path
          @pointer_manager = CachePointerManager.new(@cache_path)
          pointer = @pointer_manager.read
          raise Shoko::CacheLoadError.new(@raw_path, 'invalid pointer file') unless pointer

          @source_type = :cache_pointer
          @pointer_metadata = pointer
          @source_sha = pointer['sha256']
          @source_path = pointer['source_path']
        end

        def setup_source_reference_from_epub
          raise Shoko::FileNotFoundError, @raw_path unless File.file?(@raw_path)

          @source_type = :epub
          @source_path = @raw_path
          @source_sha = Digest::SHA256.file(@source_path).hexdigest
          @cache_path = cache_path_for_source_sha
          @pointer_manager = CachePointerManager.new(@cache_path)
          @pointer_metadata = @pointer_manager.read
        end

        def cache_path_for_source_sha
          cache_path = self.class.cache_path_for_sha(@source_sha, cache_root: @cache_root)
          raise Shoko::CacheLoadError.new(@raw_path, 'invalid sha256 digest') unless cache_path

          cache_path
        end

        def ensure_sha!
          return if @source_sha

          if @source_type == :epub
            @source_sha = Digest::SHA256.file(@source_path).hexdigest
          elsif @pointer_metadata
            @source_sha = @pointer_metadata['sha256']
          end
        end

        # --- In-memory caching of loaded payloads + layouts ---

        def load_payload
          return @payload_cache if @payload_cache

          ensure_sha!
          cache_payload(load_payload_from_store(@source_sha))
        end

        def cache_payload(payload)
          return nil unless payload

          @payload_cache = payload
          @layout_cache = normalize_layout_cache(payload.layouts)
          refresh_payload_layouts!
          payload
        end

        def load_payload_from_store(sha)
          raw = fetch_raw_payload(sha)
          return nil unless raw

          ensure_pointer_from_metadata(raw.metadata_row)
          Serializer.build_payload_from_store(raw, cache_root: @cache_root, book_sha: sha)
        rescue Shoko::Error => e
          @logger&.debug('EpubCache: failed to load cache', sha: sha.to_s, error: e.message)
          nil
        end

        def fetch_raw_payload(sha)
          return nil unless sha

          @cache_store.fetch_payload(sha)
        end

        def cache_layout!(key, payload)
          @layout_cache ||= {}
          @layout_cache[key] = deep_dup(payload)
          return unless @payload_cache

          @payload_cache.layouts ||= {}
          @payload_cache.layouts[key] = deep_dup(payload)
        end

        def update_layout_cache_from_layouts(layouts)
          @layout_cache = normalize_layout_cache(layouts)
          refresh_payload_layouts!
        end

        def refresh_payload_layouts!
          return unless @payload_cache

          @payload_cache.layouts = @layout_cache.transform_values do |value|
            deep_dup(value)
          end
        end

        def normalize_layout_cache(layouts)
          (layouts || {}).each_with_object({}) do |(key, payload), acc|
            acc[key.to_s] = deep_dup(payload)
          end
        end

        def deep_dup(obj)
          deep_dup_value(obj)
        end

        def deep_dup_value(value)
          case value
          when String
            value.dup
          when Array
            value.map { |item| deep_dup_value(item) }
          when Hash
            value.transform_values { |item| deep_dup_value(item) }
          else
            value
          end
        end

        def invalidate_and_nil
          invalidate!
          nil
        end

        def payload_valid?(payload)
          payload.is_a?(CachePayload) &&
            payload.version.to_i == CACHE_VERSION &&
            payload.book.is_a?(Shoko::Core::Models::BookData)
        end

        # --- Persistence of payloads + pointer metadata ---

        def persist_payload(book_data, layouts_hash:)
          ensure_sha!
          generated_at = Time.now.utc

          success = @cache_store.write_payload(**payload_write_params(book_data, layouts_hash, generated_at))
          return nil unless success

          metadata = pointer_metadata_for_write(generated_at, engine: cache_engine)
          write_pointer_metadata(metadata)
          metadata
        end

        def payload_write_params(book_data, layouts_hash, generated_at)
          serialized = Serializer.serialize(book_data, json: false)
          layouts_serialized = Serializer.serialize_layouts(layouts_hash)

          {
            sha: @source_sha,
            source_path: @source_path,
            source_mtime: safe_mtime(@source_path),
            generated_at: generated_at,
            serialized_book: serialized[:book],
            serialized_chapters: serialized[:chapters],
            serialized_resources: serialized[:resources],
            serialized_layouts: layouts_serialized,
          }
        end

        def write_pointer_metadata(metadata)
          @pointer_manager ||= CachePointerManager.new(@cache_path)
          @pointer_manager.write(metadata)
          @pointer_metadata = metadata
          @source_type = :cache_pointer
        end

        def pointer_metadata_for_write(generated_at, engine:)
          pointer_metadata(
            sha: @source_sha,
            source_path: @source_path,
            generated_at: generated_at.iso8601,
            engine: engine
          )
        end

        def pointer_metadata(sha:, source_path:, generated_at:, engine:)
          {
            'format' => CachePointerManager::POINTER_FORMAT,
            'version' => CachePointerManager::POINTER_VERSION,
            'sha256' => sha,
            'source_path' => source_path,
            'generated_at' => generated_at,
            'engine' => engine,
          }
        end

        def ensure_pointer_from_metadata(record)
          return unless record

          ensure_sha!
          pointer_metadata = pointer_metadata_for_record(record)
          return if pointer_current?(pointer_metadata['sha256'])

          write_pointer_metadata(pointer_metadata)
        end

        def pointer_metadata_for_record(record)
          record_engine = Serializer.value_for(record, :engine) || cache_engine
          pointer_metadata(
            sha: Serializer.value_for(record, :source_sha),
            source_path: Serializer.value_for(record, :source_path),
            generated_at: pointer_generated_at(record),
            engine: record_engine
          )
        end

        def pointer_generated_at(record)
          raw = Serializer.value_for(record, :generated_at)
          time = Serializer.coerce_time(raw)
          (time || Time.now.utc).iso8601
        end

        def pointer_current?(sha)
          current = @pointer_manager&.read
          current && current['sha256'] == sha
        end

        def cache_engine
          engine = @cache_store.engine
          engine || JsonCacheStore::ENGINE
        rescue Shoko::Error
          JsonCacheStore::ENGINE
        end

        def payload_matches_source?(payload, strict:)
          return true if cache_file? && !payload.source_path

          ensure_sha!
          return false unless payload.source_sha256 == @source_sha

          mtime_matches?(payload, strict: strict)
        end

        def mtime_matches?(payload, strict:)
          source_mtime = safe_mtime(@source_path)
          payload_mtime = payload.source_mtime
          return true unless source_mtime && payload_mtime

          tolerance = strict ? 1e-3 : 1.0
          (source_mtime.to_f - payload_mtime.to_f).abs <= tolerance
        end

        def safe_mtime(path)
          File.mtime(path)&.utc
        end
      end
    end
  end
end

require_relative 'cache/epub/serializer'
