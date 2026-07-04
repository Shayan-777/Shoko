# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      # Manifest helpers for `JsonCacheStore` (cache listing).
      class JsonCacheStore
        MANIFEST_ROWS_CACHE_ENABLED_KEY = :shoko_manifest_rows_cache_enabled
        MANIFEST_LOCK_FILENAME = 'cache_manifest.lock'

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
        end

        private

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

        def self.read_manifest_file(path)
          return [] unless File.file?(path)

          data = JSON.parse(File.read(path))
          data.is_a?(Array) ? data : []
        rescue JSON::ParserError, SystemCallError, IOError => e
          discard_corrupt_manifest(e)
        end
        private_class_method :read_manifest_file

        # A corrupt or unreadable manifest reads as empty so a damaged cache
        # never crashes the library listing. The realizable failures here are
        # bounded (parse + filesystem), so this stays a narrow rescue.
        def self.discard_corrupt_manifest(_error)
          []
        end
        private_class_method :discard_corrupt_manifest

        class << self
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
      end
    end
  end
end
