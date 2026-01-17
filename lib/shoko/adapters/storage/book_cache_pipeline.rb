# frozen_string_literal: true

require_relative '../../shared/errors'
require_relative 'epub_cache'
require_relative '../book_sources/epub_importer'
require_relative 'json_cache_store'
require_relative 'cache_pointer_manager'
require_relative '../monitoring/logger'
require_relative '../book_sources/source_fingerprint'
require 'fileutils'
require 'time'

module Shoko
  module Adapters::Storage
    # Coordinates importing EPUB files and storing/loading JSON-backed caches.
    # Provides a single entry point that ensures cache integrity, re-importing
    # whenever a cache is missing, corrupted, or outdated.
    class BookCachePipeline
      # Result payload returned by cache pipeline loads.
      Result = Struct.new(
        :book,
        :cache_path,
        :source_path,
        :loaded_from_cache,
        :payload,
        keyword_init: true
      )

      # Wraps manifest row hashes with typed accessors.
      class ManifestRow
        def self.from(row)
          return nil unless row.is_a?(Hash)

          new(row)
        end

        def initialize(row)
          source_path, source_mtime, source_size, source_fingerprint, updated_at, source_sha =
            row.values_at(
              'source_path',
              'source_mtime',
              'source_size_bytes',
              'source_fingerprint',
              'updated_at',
              'source_sha'
            )
          fingerprint_value = source_fingerprint.to_s.strip
          fingerprint_value = nil if fingerprint_value.empty?

          @data = {
            source_path: source_path.to_s,
            source_mtime: source_mtime,
            source_size_bytes: source_size,
            source_fingerprint: fingerprint_value,
            updated_at: updated_at.to_f,
            source_sha: source_sha.to_s.strip,
          }
        end

        def path_match?(source_path)
          @data[:source_path] == source_path
        end

        def mtime_match?(source_mtime)
          raw_mtime = @data[:source_mtime]
          return false unless raw_mtime

          (raw_mtime.to_f - source_mtime.to_f).abs <= 1.0
        end

        def size_match?(source_size_bytes)
          raw_size = @data[:source_size_bytes]
          return true unless raw_size

          raw_size.to_i == source_size_bytes.to_i
        end

        def fingerprint_value
          @data[:source_fingerprint]
        end

        def updated_at
          @data[:updated_at]
        end

        def source_sha
          sha = @data[:source_sha]
          sha.empty? ? nil : sha
        end
      end
      private_constant :ManifestRow

      # Filters manifest rows by source fingerprint, keeping untagged rows.
      class FingerprintFilter
        def initialize(source_path)
          @source_path = source_path
          @fingerprint = nil
          @fingerprint_blank = false
        end

        def call(rows)
          matches = rows.select { |row| include_row?(row) }
          [matches, applied?, blank?]
        end

        private

        def include_row?(row)
          value = row.fingerprint_value
          return true unless value

          ensure_fingerprint
          return false if @fingerprint_blank

          value == @fingerprint
        end

        def ensure_fingerprint
          return if @fingerprint

          @fingerprint = Shoko::Adapters::BookSources::SourceFingerprint.compute(@source_path).to_s
          @fingerprint_blank = @fingerprint.empty?
        end

        def applied?
          !!@fingerprint
        end

        def blank?
          @fingerprint_blank
        end
      end
      private_constant :FingerprintFilter

      # Finds the best manifest SHA match for a source file.
      class ManifestShaFinder
        def initialize(rows:, source_path:, source_mtime:, source_size_bytes:)
          @rows = rows.each_with_object([]) do |row, acc|
            wrapper = ManifestRow.from(row)
            acc << wrapper if wrapper
          end
          @source_path = source_path
          @source_mtime = source_mtime
          @source_size_bytes = source_size_bytes
        end

        def sha
          best = best_match
          best&.source_sha
        rescue StandardError
          nil
        end

        private

        def best_match
          filtered_rows.max_by(&:updated_at)
        end

        def filtered_rows
          fingerprint_matches(size_matches(mtime_matches(path_matches)))
        end

        def path_matches
          @rows.select { |row| row.path_match?(@source_path) }
        end

        def mtime_matches(rows)
          rows.select { |row| row.mtime_match?(@source_mtime) }
        end

        def size_matches(rows)
          rows.select { |row| row.size_match?(@source_size_bytes) }
        end

        def fingerprint_matches(rows)
          matches, applied, blank = FingerprintFilter.new(@source_path).call(rows)
          return rows unless applied
          return [] if blank

          matches
        end
      end
      private_constant :ManifestShaFinder

      # Removes stale pointer cache files after a rebuild.
      class PointerCacheCleaner
        def initialize(cache_path, rebuilt_path)
          @cache_path = cache_path
          @rebuilt_path = rebuilt_path
        end

        def call
          return unless @rebuilt_path
          return if same_path?

          FileUtils.rm_f(@cache_path)
        rescue StandardError
          nil
        end

        private

        def same_path?
          File.expand_path(@cache_path) == File.expand_path(@rebuilt_path)
        end
      end
      private_constant :PointerCacheCleaner

      # Rebuilds pointer caches by loading the original source file.
      class PointerRebuilder
        def initialize(cache:, formatting_service:, load_callback:)
          @cache = cache
          @formatting_service = formatting_service
          @load_callback = load_callback
          @cache_class = cache.class
        end

        def call
          return nil unless pointer_source_valid?

          rebuild
        rescue StandardError => e
          log_failure(e)
          nil
        end

        private

        def pointer_source_valid?
          path = source_path
          return false if path.empty?
          return false if @cache_class.cache_file?(path)

          File.file?(path)
        rescue StandardError
          false
        end

        def rebuild
          rebuilt = @load_callback.call(source_path, formatting_service: @formatting_service)
          PointerCacheCleaner.new(cache_path, rebuilt&.cache_path).call
          rebuilt
        end

        def cache_path
          @cache.cache_path
        end

        def source_path
          @source_path ||= @cache.source_path.to_s
        end

        def log_failure(error)
          Shoko::Adapters::Monitoring::Logger.error(
            'Pointer cache rebuild failed',
            cache: cache_path,
            source: source_path,
            error: error.message
          )
        end
      end
      private_constant :PointerRebuilder

      # Ensures pointer metadata exists on disk for a cached source.
      class PointerFileEnsurer
        def initialize(pointer_path:, sha:, source_path:, manager_class:)
          @pointer_path = pointer_path
          @sha = sha
          @source_path = source_path
          @manager_class = manager_class
        end

        def call
          manager = @manager_class.new(@pointer_path)
          existing = manager.read
          return if current?(existing)

          manager.write(metadata)
        rescue StandardError
          nil
        end

        private

        def current?(existing)
          existing && existing['sha256'] == @sha && existing['source_path'].to_s == @source_path
        end

        def metadata
          {
            'format' => @manager_class::POINTER_FORMAT,
            'version' => @manager_class::POINTER_VERSION,
            'sha256' => @sha,
            'source_path' => @source_path,
            'generated_at' => Time.now.utc.iso8601,
            'engine' => JsonCacheStore::ENGINE,
          }
        end
      end
      private_constant :PointerFileEnsurer

      # Validates cached payload completeness.
      class CacheIntegrityChecker
        def initialize(cache:, payload:)
          @cache = cache
          @payload = payload
        end

        def incomplete?
          chapters = Array(book&.chapters)
          return true if chapters.empty? || chapters.any?(&:nil?)

          !@cache.chapters_complete?(chapters.length, generation: chapters_generation)
        rescue StandardError
          true
        end

        private

        def book
          @payload&.book
        end

        def chapters_generation
          book&.chapters_generation
        rescue NoMethodError
          nil
        end
      end
      private_constant :CacheIntegrityChecker

      # Tracks whether a payload originated from cache.
      class CacheStatus
        def self.hit(cache_marker)
          new(cache_marker)
        end

        def self.miss
          new(nil)
        end

        def initialize(cache_marker)
          @cache_marker = cache_marker
        end

        def mark_rebuilt
          @cache_marker = nil
        end

        def loaded_from_cache?
          !!@cache_marker
        end
      end
      private_constant :CacheStatus

      # Bundles payload and cache status for cache session operations.
      class PayloadContext
        attr_reader :payload, :cache_status

        def initialize(payload:, cache_status:)
          @payload = payload
          @cache_status = cache_status
        end
      end
      private_constant :PayloadContext

      # Handles cache loading/rebuilding for a specific cache instance.
      class CacheSession
        def initialize(cache:, formatting_service:, importer_class:, load_callback:, progress_reporter: nil)
          @cache = cache
          @formatting_service = formatting_service
          @importer_class = importer_class
          @load_callback = load_callback
          @progress_reporter = progress_reporter
        end

        def load
          cache_file = @cache.cache_file?
          report('Loading cached book...') if cache_file
          result = result_from_initial_payload
          return result if result

          return rebuild_from_pointer_or_raise if cache_file

          import_and_result
        end

        def fast_load
          report('Loading cached book...')
          payload, cache_status = payload_from_cache
          context = PayloadContext.new(payload: payload, cache_status: cache_status)
          result_from_payload_or_nil(context)
        end

        private

        def initial_payload
          payload = @cache.cache_file? ? @cache.read_cache(strict: true) : payload_from_source
          payload || payload_from_source
        end

        def payload_from_cache
          payload = @cache.read_cache(strict: true)
          cache_status = CacheStatus.hit(payload)
          payload ||= rebuild_cache
          [payload, cache_status]
        end

        def payload_from_source
          @cache.load_for_source(strict: true) || @cache.load_for_source(strict: false)
        end

        def result_from_initial_payload
          payload = initial_payload
          payload && result_from_payload(
            PayloadContext.new(payload: payload, cache_status: CacheStatus.hit(payload))
          )
        end

        def result_from_payload(context)
          payload = rebuild_if_incomplete(context)
          result_for(payload, loaded_from_cache: context.cache_status.loaded_from_cache?)
        end

        def result_from_payload_or_nil(context)
          context.payload && begin
            payload = rebuild_if_incomplete(context)
            payload && result_for(payload, loaded_from_cache: context.cache_status.loaded_from_cache?)
          end
        end

        def rebuild_if_incomplete(context)
          payload = context.payload
          checker = CacheIntegrityChecker.new(cache: @cache, payload: payload)
          return payload unless checker.incomplete?

          context.cache_status.mark_rebuilt
          rebuild_cache
        end

        def result_for(payload, loaded_from_cache:)
          book = payload.book
          cache_path = @cache.cache_path
          source_path = payload.source_path || @cache.source_path
          Result.new(
            book: book,
            cache_path: cache_path,
            source_path: source_path,
            loaded_from_cache: loaded_from_cache,
            payload: payload
          )
        end

        def import_and_result
          context = PayloadContext.new(payload: rebuild_cache, cache_status: CacheStatus.miss)
          result = result_from_payload_or_nil(context)
          return result if result

          raise Shoko::CacheLoadError.new(@cache.cache_path, 'cache write failed')
        end

        def rebuild_cache
          importer = @importer_class.new(
            formatting_service: @formatting_service,
            progress_reporter: @progress_reporter
          )
          book_data = importer.import(@cache.source_path)
          report('Creating JSON cache...', progress: 0.0)
          @cache.write_book!(book_data)
          report('Finalizing cache...', progress: 1.0)
          payload_from_source
        end

        def rebuild_from_pointer_or_raise
          rebuilt = rebuild_from_pointer
          return rebuilt if rebuilt

          raise Shoko::CacheLoadError, @cache.cache_path
        end

        def rebuild_from_pointer
          report('Rebuilding cache from source...')
          PointerRebuilder.new(
            cache: @cache,
            formatting_service: @formatting_service,
            load_callback: @load_callback
          ).call
        end

        def report(message, progress: nil)
          reporter = @progress_reporter
          return unless reporter
          return if message.nil? || message.to_s.strip.empty?

          if reporter.respond_to?(:call)
            reporter.call(message: message, progress: progress)
          elsif reporter.respond_to?(:update_status)
            reporter.update_status(message: message, progress: progress)
          end
        rescue StandardError
          nil
        end
      end
      private_constant :CacheSession

      # Raises standardized load errors for pipeline failures.
      class LoadErrorHandler
        def initialize(path)
          @path = path
        end

        def call(error)
          message = error.message
          Shoko::Adapters::Monitoring::Logger.error('Book cache pipeline failed', path: @path, error: message)
          raise Shoko::EPUBParseError.new(message, @path)
        end
      end
      private_constant :LoadErrorHandler

      def initialize(cache_class: EpubCache, cache_root: CachePaths.cache_root, progress_reporter: nil)
        @cache_class = cache_class
        @cache_root = cache_root
        @importer_class = Shoko::Adapters::BookSources::EpubImporter
        @pointer_manager_class = CachePointerManager
        @progress_reporter = progress_reporter
      end

      def load(path, formatting_service: nil)
        perform_load(path, formatting_service)
      rescue StandardError => e
        raise if e.is_a?(Shoko::Error)

        LoadErrorHandler.new(path).call(e)
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
        @cache_class.new(path, cache_root: @cache_root)
      end

      def cache_session(cache, formatting_service)
        CacheSession.new(
          cache: cache,
          formatting_service: formatting_service,
          importer_class: @importer_class,
          load_callback: method(:load),
          progress_reporter: @progress_reporter
        )
      end

      def fast_source_path?(expanded)
        return false if @cache_class.cache_file?(expanded)

        File.file?(expanded)
      rescue StandardError
        false
      end

      def fast_load_for_source(source_path, formatting_service)
        perform_fast_load(source_path, formatting_service)
      rescue StandardError => e
        Shoko::Adapters::Monitoring::Logger.debug('Fast cache load failed', path: source_path, error: e.message)
        nil
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
        rows = JsonCacheStore.manifest_rows(@cache_root)
        return nil if rows.empty?

        ManifestShaFinder.new(
          rows: rows,
          source_path: source_path,
          source_mtime: source_mtime,
          source_size_bytes: source_size_bytes
        ).sha
      rescue StandardError
        nil
      end

      def ensure_pointer_file(pointer_path, sha, source_path)
        PointerFileEnsurer.new(
          pointer_path: pointer_path,
          sha: sha,
          source_path: source_path,
          manager_class: @pointer_manager_class
        ).call
      end

      def report(message, progress: nil)
        reporter = @progress_reporter
        return unless reporter
        return if message.nil? || message.to_s.strip.empty?

        if reporter.respond_to?(:call)
          reporter.call(message: message, progress: progress)
        elsif reporter.respond_to?(:update_status)
          reporter.update_status(message: message, progress: progress)
        end
      rescue StandardError
        nil
      end
    end
  end
end
