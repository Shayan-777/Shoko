# frozen_string_literal: true

require 'fileutils'
require 'json'
require_relative 'atomic_file_writer'
require 'shoko/shared/resilient_diagnostics'

module Shoko
  module Adapters
    module Storage
      # Owns manifest locking, atomic updates, and the optional process-local
      # read cache for JSON cache listings.
      class JsonCacheManifestStore
        FILENAME = 'cache_manifest.json'
        LOCK_FILENAME = 'cache_manifest.lock'
        CACHE_ENABLED_KEY = :shoko_manifest_rows_cache_enabled

        @cache_mutex = Mutex.new
        @cache_data = {}

        class << self
          def with_cache(enabled:)
            previous = Thread.current[CACHE_ENABLED_KEY]
            Thread.current[CACHE_ENABLED_KEY] = enabled == true
            yield
          ensure
            Thread.current[CACHE_ENABLED_KEY] = previous
          end

          def cache_enabled?(runtime_config: nil)
            override = Thread.current[CACHE_ENABLED_KEY]
            return override unless override.nil?

            runtime_config.nil? || !runtime_config.manifest_rows_cache_disabled?
          end

          def clear_cache(cache_root = nil)
            @cache_mutex.synchronize do
              cache_root ? @cache_data.delete(cache_key(cache_root)) : @cache_data.clear
            end
          end

          def rows(cache_root, runtime_config: nil)
            path = File.join(cache_root, FILENAME)
            return [] unless File.file?(path)

            if cache_enabled?(runtime_config: runtime_config)
              cached = cached_rows(cache_root, path)
              return cached if cached
            end

            result = normalize(read_file(path))
            cache_rows(cache_root, path, result) if cache_enabled?(runtime_config: runtime_config)
            clone_rows(result)
          end

          private

          def read_file(path)
            data = JSON.parse(File.read(path))
            data.is_a?(Array) ? data : []
          rescue JSON::ParserError, SystemCallError, IOError
            []
          end

          def cached_rows(cache_root, path)
            stat = File.stat(path)
            entry = @cache_mutex.synchronize { @cache_data[cache_key(cache_root)] }
            return nil unless entry
            return nil unless (entry[:mtime] - stat.mtime.to_f).abs < Float::EPSILON && entry[:size] == stat.size

            clone_rows(entry[:rows])
          end

          def cache_rows(cache_root, path, rows)
            stat = File.stat(path)
            entry = { mtime: stat.mtime.to_f, size: stat.size, rows: normalize(rows) }
            @cache_mutex.synchronize { @cache_data[cache_key(cache_root)] = entry }
          end

          def normalize(rows) = Array(rows).filter_map { |row| row.dup if row.is_a?(Hash) }
          def clone_rows(rows) = rows.map(&:dup)
          def cache_key(cache_root) = File.expand_path(cache_root.to_s)
        end

        def initialize(cache_root:, logger: nil)
          @cache_root = cache_root
          @logger = logger
        end

        def update(metadata_row, cache_size_bytes:)
          row = metadata_row.merge('cache_size_bytes' => cache_size_bytes.to_i)
          locked_update do |rows|
            rows.reject! { |entry| entry['source_sha'] == row['source_sha'] }
            rows << row
          end
        end

        def remove(sha)
          locked_update { |rows| rows.reject! { |entry| entry['source_sha'] == sha } }
        end

        private

        def locked_update
          FileUtils.mkdir_p(@cache_root)
          File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
            lock.flock(File::LOCK_EX)
            rows = fresh_rows
            yield rows
            AtomicFileWriter.write(path, JSON.generate(rows))
          end
          self.class.clear_cache(@cache_root)
          true
        # resilient-boundary
        rescue StandardError => e
          Shoko::Shared::ResilientDiagnostics.debug(
            @logger, 'json_cache.manifest_update_failed', error: e.class.name, message: e.message
          )
          false
        end

        def fresh_rows
          return [] unless File.file?(path)

          data = JSON.parse(File.read(path))
          data.is_a?(Array) ? data.grep(Hash) : []
        rescue JSON::ParserError, SystemCallError, IOError
          []
        end

        def path = File.join(@cache_root, FILENAME)
        def lock_path = File.join(@cache_root, LOCK_FILENAME)
      end
    end
  end
end
