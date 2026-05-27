# frozen_string_literal: true

require 'time'

require_relative '../../application/ports/outbound/background_worker_builder'
require_relative '../../application/ports/outbound/display_metadata_cache'
require_relative '../../application/ports/outbound/file_probe'
require_relative '../../application/ports/outbound/library_scanner'
require_relative '../../application/ports/outbound/metadata_reader'
require_relative '../../shared/errors'

module Shoko
  module Application
    module UseCases
      # Facade providing catalog data (cached books, scan status, metadata) to higher layers.
      # Wraps the infrastructure scanner/metadata helpers so presentation never touches them directly.
      class CatalogService
        DISPLAY_METADATA_KEYS = %i[title author authors author_str year language].freeze
        ERROR_METADATA = Object.new.freeze

        def initialize(library_scanner:, metadata_reader:, file_probe:, cached_library_repository: nil,
                       display_metadata_cache: nil, background_worker_builder: nil,
                       recent_files_repository: nil, logger: nil)
          unless library_scanner.is_a?(Shoko::Application::Ports::Outbound::LibraryScanner)
            raise ArgumentError, 'library_scanner must implement Application::Ports::Outbound::LibraryScanner'
          end
          unless metadata_reader.is_a?(Shoko::Application::Ports::Outbound::MetadataReader)
            raise ArgumentError, 'metadata_reader must implement Application::Ports::Outbound::MetadataReader'
          end
          unless file_probe.is_a?(Shoko::Application::Ports::Outbound::FileProbe)
            raise ArgumentError, 'file_probe must implement Application::Ports::Outbound::FileProbe'
          end
          validate_optional_port(display_metadata_cache,
                                 Shoko::Application::Ports::Outbound::DisplayMetadataCache,
                                 'display_metadata_cache')
          validate_optional_port(background_worker_builder,
                                 Shoko::Application::Ports::Outbound::BackgroundWorkerBuilder,
                                 'background_worker_builder')

          @scanner = library_scanner
          @cached_library_repository = cached_library_repository
          @display_metadata_cache = display_metadata_cache
          @background_worker_builder = background_worker_builder
          @recent_files_repository = recent_files_repository
          @metadata_reader = metadata_reader
          @logger = logger
          @file_probe = file_probe
          @metadata_cache = {}
          @display_metadata_memory = {}
          @display_metadata_inflight = {}
          @metadata_mutex = Mutex.new
          @metadata_refresh_pending = false
          @display_metadata_worker = nil
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

        def start_scan(force: false, preserve_entries: false)
          if preserve_entries
            @scanner.start_scan(force: force, preserve_entries: preserve_entries)
          else
            @scanner.start_scan(force: force)
          end
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
        ensure
          cleanup_display_metadata_worker
        end

        def metadata_for(path)
          return {} unless path

          cached = exact_metadata_from_memory(path)
          return cached if cached

          fingerprint = metadata_fingerprint(path: path, size: nil, modified: nil)
          cached_entry = fetch_display_cache_entry(fingerprint)
          if cached_entry && cached_entry[:status] == :ok
            return remember_exact_metadata(path, normalize_hash(cached_entry[:metadata], context: 'book_metadata'))
          end

          metadata = extract_book_metadata(path)
          write_display_success(fingerprint, metadata)
          remember_display_metadata(metadata_cache_key(fingerprint), display_metadata(metadata))
          remember_exact_metadata(path, metadata)
        rescue Shoko::Error => e
          write_display_error(fingerprint, e) if defined?(fingerprint) && fingerprint
          raise
        end

        def display_metadata_for(path, size: nil, modified: nil)
          return {} unless path

          fingerprint = metadata_fingerprint(path: path, size: size, modified: modified)
          key = metadata_cache_key(fingerprint)
          memory_hit, memory_value = display_metadata_from_memory(key)
          return display_metadata_result(memory_value) if memory_hit

          cached_entry = fetch_display_cache_entry(fingerprint)
          return remember_display_cache_entry(key, cached_entry) if cached_entry

          schedule_display_metadata_load(fingerprint, key)
          {}
        end

        def metadata_work_pending?
          @metadata_mutex.synchronize { @display_metadata_inflight.any? }
        end

        def metadata_refresh_pending?
          @metadata_mutex.synchronize { @metadata_refresh_pending == true }
        end

        def consume_metadata_refresh!
          @metadata_mutex.synchronize do
            pending = @metadata_refresh_pending == true
            @metadata_refresh_pending = false
            pending
          end
        end

        def size_for(path)
          return 0 unless path

          @file_probe.size(path) || 0
        end

        def clear_metadata_cache
          @metadata_mutex.synchronize do
            @metadata_cache.clear
            @display_metadata_memory.clear
          end
        end

        private

        def self.validate_optional_port(value, port, name)
          return if value.nil? || value.is_a?(port)

          raise ArgumentError, "#{name} must implement #{port.name}"
        end

        def validate_optional_port(value, port, name)
          self.class.validate_optional_port(value, port, name)
        end

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

        def extract_book_metadata(path)
          normalize_hash(@metadata_reader.extract_metadata(path), context: 'book_metadata')
        end

        def display_metadata(metadata)
          source = normalize_hash(metadata, context: 'book_metadata')
          DISPLAY_METADATA_KEYS.each_with_object({}) do |key, acc|
            acc[key] = source[key] if source.key?(key)
          end
        end

        def exact_metadata_from_memory(path)
          @metadata_mutex.synchronize { @metadata_cache[path.to_s] }
        end

        def remember_exact_metadata(path, metadata)
          @metadata_mutex.synchronize { @metadata_cache[path.to_s] = metadata }
        end

        def display_metadata_from_memory(key)
          @metadata_mutex.synchronize do
            [@display_metadata_memory.key?(key), @display_metadata_memory[key]]
          end
        end

        def remember_display_metadata(key, metadata)
          @metadata_mutex.synchronize { @display_metadata_memory[key] = metadata || {} }
        end

        def remember_display_error(key)
          @metadata_mutex.synchronize { @display_metadata_memory[key] = ERROR_METADATA }
        end

        def remember_display_cache_entry(key, entry)
          if entry[:status] == :ok
            metadata = normalize_hash(entry[:metadata] || {}, context: 'display_metadata')
            remember_display_metadata(key, metadata)
            return metadata
          end

          remember_display_error(key)
          {}
        end

        def display_metadata_result(value)
          value.equal?(ERROR_METADATA) ? {} : value
        end

        def fetch_display_cache_entry(fingerprint)
          return nil unless @display_metadata_cache

          @display_metadata_cache.fetch(**fingerprint)
        rescue Shoko::Error => e
          log_metadata_cache_debug('catalog.display_metadata_cache.fetch_failed', e)
          nil
        end

        def write_display_success(fingerprint, metadata)
          return unless @display_metadata_cache

          @display_metadata_cache.write_success(**fingerprint, metadata: display_metadata(metadata))
        rescue Shoko::Error => e
          log_metadata_cache_debug('catalog.display_metadata_cache.write_success_failed', e)
          nil
        end

        def write_display_error(fingerprint, error)
          return unless @display_metadata_cache

          @display_metadata_cache.write_error(
            **fingerprint,
            error_class: error.class.name,
            error_message: error.message
          )
        rescue Shoko::Error => e
          log_metadata_cache_debug('catalog.display_metadata_cache.write_error_failed', e)
          nil
        end

        def schedule_display_metadata_load(fingerprint, key)
          return unless @background_worker_builder
          return unless mark_display_metadata_inflight(key)

          worker = display_metadata_worker
          return clear_display_metadata_inflight(key) unless worker

          worker.submit { load_display_metadata(fingerprint, key) }
        rescue Shoko::Error => e
          clear_display_metadata_inflight(key)
          log_metadata_cache_debug('catalog.display_metadata_cache.submit_failed', e)
        end

        def load_display_metadata(fingerprint, key)
          metadata = extract_book_metadata(fingerprint[:path])
          write_display_success(fingerprint, metadata)
          remember_display_metadata(key, display_metadata(metadata))
        rescue Shoko::Error, ArgumentError, TypeError => e
          write_display_error(fingerprint, e)
          remember_display_error(key)
        ensure
          finish_display_metadata_job(key)
        end

        def mark_display_metadata_inflight(key)
          @metadata_mutex.synchronize do
            return false if @display_metadata_inflight.key?(key)

            @display_metadata_inflight[key] = true
            true
          end
        end

        def clear_display_metadata_inflight(key)
          @metadata_mutex.synchronize { @display_metadata_inflight.delete(key) }
          nil
        end

        def finish_display_metadata_job(key)
          @metadata_mutex.synchronize do
            @display_metadata_inflight.delete(key)
            @metadata_refresh_pending = true
          end
        end

        def display_metadata_worker
          @metadata_mutex.synchronize do
            @display_metadata_worker ||= @background_worker_builder&.build(
              logger: @logger,
              name: 'browse-metadata-cache-worker'
            )
          end
        end

        def cleanup_display_metadata_worker
          worker = @metadata_mutex.synchronize do
            worker_ref = @display_metadata_worker
            @display_metadata_worker = nil
            worker_ref
          end
          worker&.shutdown
        rescue Shoko::Error => e
          log_metadata_cache_debug('catalog.display_metadata_cache.cleanup_failed', e)
        end

        def metadata_fingerprint(path:, size:, modified:)
          {
            path: path.to_s,
            size: normalized_size(size.nil? ? fingerprint_size_for(path) : size),
            modified: normalized_modified(modified || modified_for(path)),
          }
        end

        def metadata_cache_key(fingerprint)
          [
            fingerprint.fetch(:path),
            fingerprint.fetch(:size),
            fingerprint.fetch(:modified),
          ].join("\0")
        end

        # Returns the file's modification timestamp (ISO 8601) or nil if
        # the file is gone. Filesystem exceptions are handled inside the
        # `FileProbe` adapter; this method sees only a typed result.
        def modified_for(path)
          normalized_modified(@file_probe.mtime(path))
        end

        def fingerprint_size_for(path)
          @file_probe.size(path)
        end

        # Integer-coerce while accepting nil/blank/non-numeric inputs as
        # nil. `Integer(..., exception: false)` returns nil on parse
        # failure without needing a rescue, so this normalizer is fully
        # exception-free.
        def normalized_size(value)
          return nil if value.nil?

          string = value.to_s.strip
          return nil if string.empty?

          Integer(string, exception: false)
        end

        def normalized_modified(value)
          return nil if value.nil?

          string = value.to_s.strip
          string.empty? ? nil : string
        end

        # Logger-write failures (Shoko::LoggingError) deliberately surface
        # — the LoggerAdapter is designed to raise on broken output
        # streams and that signal must not be swallowed by observability
        # code. If logging itself can crash a cache-debug path, that's a
        # disk/stream failure worth seeing.
        def log_metadata_cache_debug(event, error)
          @logger&.debug(event, error: error.class.name, message: error.message)
        end
      end
    end
  end
end
