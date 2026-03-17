# frozen_string_literal: true

require_relative '../../shared/errors'
require_relative 'epub_cache'
require_relative 'json_cache_store'
require_relative 'cache_pointer_manager'
require_relative '../../shared/source_fingerprint'
require_relative '../../adapters/book_sources/format_registry'
require_relative 'book_cache_pipeline/manifest_row'
require_relative 'book_cache_pipeline/fingerprint_filter'
require_relative 'book_cache_pipeline/manifest_sha_finder'
require_relative 'book_cache_pipeline/pointer_file_ensurer'
require_relative 'book_cache_pipeline/cache_integrity_checker'
require_relative 'book_cache_pipeline/cache_status'
require_relative 'book_cache_pipeline/payload_context'
require_relative 'book_cache_pipeline/cache_session'
require_relative 'book_cache_pipeline/load_error_handler'
require_relative '../support/lifecycle_helpers'
require 'fileutils'
require 'time'

module Shoko
  module Adapters
    module Storage
      # Coordinates importing EPUB files and storing/loading JSON-backed caches.
      # Provides a single entry point that ensures cache integrity, re-importing
      # whenever a cache is missing, corrupted, or outdated.
      class BookCachePipeline
        include Shoko::Adapters::Support::LifecycleHelpers

        # Result payload returned by cache pipeline loads.
        Result = Struct.new(
          :book,
          :cache_path,
          :source_path,
          :loaded_from_cache,
          :payload
        )
        KEYWORD_PARAMETER_KINDS = %i[key keyreq].freeze

        def initialize(cache_class: EpubCache, cache_root: CachePaths.cache_root,
                       default_importer_class: nil, progress_reporter: nil, logger: nil, runtime_config: nil,
                       image_cache_warmup: nil)
          @cache_class = cache_class
          @cache_root = cache_root
          @default_importer_class = default_importer_class
          @pointer_manager_class = CachePointerManager
          @progress_reporter = progress_reporter
          @logger = logger
          @runtime_config = runtime_config
          @image_cache_warmup = image_cache_warmup
        end

        def load(path, formatting_service: nil)
          perform_load(path, formatting_service)
        rescue StandardError => e
          raise if e.is_a?(Shoko::Error)

          raise_load_error(path, e)
        end

        private

        def perform_load(path, formatting_service)
          report('Checking cache...')
          expanded = File.expand_path(path)
          fast = fast_load_if_available(expanded, formatting_service)
          return fast if fast

          cache = build_cache(expanded)
          cache_session(cache, formatting_service).load
        end

        def fast_load_if_available(expanded, formatting_service)
          return nil unless fast_source_path?(expanded)

          fast_load_for_source(expanded, formatting_service)
        end

        def build_cache(path)
          kwargs = {
            cache_root: @cache_root,
            logger: @logger,
          }
          kwargs[:runtime_config] = @runtime_config if cache_supports_runtime_config?
          @cache_class.new(path, **kwargs)
        end

        def cache_session(cache, formatting_service)
          CacheSession.new(
            cache: cache,
            formatting_service: formatting_service,
            importer_class: @default_importer_class,
            load_callback: method(:load),
            progress_reporter: @progress_reporter,
            runtime_config: @runtime_config,
            logger: @logger,
            image_cache_warmup: @image_cache_warmup
          )
        end

        def fast_source_path?(expanded)
          return false if @cache_class.cache_file?(expanded)

          File.file?(expanded)
        end

        def fast_load_for_source(source_path, formatting_service)
          perform_fast_load(source_path, formatting_service)
        end

        def perform_fast_load(source_path, formatting_service)
          report('Looking up cached data...')
          pointer_path, sha = pointer_for_source(source_path)
          return nil unless pointer_path

          ensure_pointer_file(pointer_path, sha, source_path)

          cache = build_cache(pointer_path)
          cache_session(cache, formatting_service).fast_load
        end

        def pointer_for_source(source_path)
          sha = sha_for_source(source_path)
          return nil unless sha

          pointer_path = pointer_path_for_sha(sha)
          return nil unless pointer_path

          [pointer_path, sha]
        end

        def sha_for_source(source_path)
          source_mtime = File.mtime(source_path).utc
          source_size_bytes = File.size(source_path)
          sha_from_manifest(source_path, source_mtime, source_size_bytes)
        end

        def pointer_path_for_sha(sha)
          @cache_class.cache_path_for_sha(sha, cache_root: @cache_root)
        end

        def sha_from_manifest(source_path, source_mtime, source_size_bytes)
          rows = JsonCacheStore.manifest_rows(@cache_root, runtime_config: @runtime_config)
          return nil if rows.empty?

          ManifestShaFinder.new(
            rows: rows,
            source_path: source_path,
            source_mtime: source_mtime,
            source_size_bytes: source_size_bytes,
            runtime_config: @runtime_config
          ).sha
        end

        def cache_supports_runtime_config?
          parameters = @cache_class.instance_method(:initialize).parameters
          parameters.any? { |kind, name| KEYWORD_PARAMETER_KINDS.include?(kind) && name == :runtime_config }
        end

        def ensure_pointer_file(pointer_path, sha, source_path)
          PointerFileEnsurer.new(
            pointer_path: pointer_path,
            sha: sha,
            source_path: source_path,
            manager_class: @pointer_manager_class,
            logger: @logger
          ).call
        end

        def raise_load_error(path, error)
          LoadErrorHandler.new(path, logger: @logger).call(error)
        end
      end
    end
  end
end
