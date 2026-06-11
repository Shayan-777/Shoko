# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      # Manifest helpers for `JsonCacheStore` (cache listing).
      class JsonCacheStore
        MANIFEST_ROWS_CACHE_ENABLED_KEY = :shoko_manifest_rows_cache_enabled

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

        def update_manifest(metadata_row, cache_size_bytes:)
          row = metadata_row.merge('cache_size_bytes' => cache_size_bytes.to_i)
          manifest = self.class.manifest_rows(@cache_root, runtime_config: @runtime_config)
          manifest.reject! { |entry| entry['source_sha'] == row['source_sha'] }
          manifest << row
          AtomicFileWriter.write(manifest_path, JSON.generate(manifest))
          self.class.clear_manifest_rows_cache(@cache_root)
        # resilient-boundary
        rescue StandardError => e
          record_cache_error('manifest write failed', e)
        end

        def remove_from_manifest(sha)
          manifest = self.class.manifest_rows(@cache_root, runtime_config: @runtime_config)
          manifest.reject! { |entry| entry['source_sha'] == sha }
          AtomicFileWriter.write(manifest_path, JSON.generate(manifest))
          self.class.clear_manifest_rows_cache(@cache_root)
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

          def manifest_rows_cache_mutex
            @manifest_rows_cache_mutex ||= Mutex.new
          end

          def manifest_rows_cache_data
            @manifest_rows_cache_data ||= {}
          end

          def manifest_cache_key(cache_root)
            File.expand_path(cache_root.to_s)
          end
        end
      end
    end
  end
end
