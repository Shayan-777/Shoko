# frozen_string_literal: true

require 'digest'
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
        CACHE_VERSION   = 5
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
          @logger&.debug('EpubCache: failed to write cache', path: @cache_path,
                                                             error: e.message)
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
          @logger&.debug('EpubCache: failed to update layouts', path: @cache_path,
                                                                error: e.message)
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
      end
    end
  end
end

require_relative 'cache/epub/serializer'
require_relative 'cache/epub/source_reference'
require_relative 'cache/epub/memory_cache'
require_relative 'cache/epub/persistence'
