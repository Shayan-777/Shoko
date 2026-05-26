# frozen_string_literal: true

require_relative '../../application/ports/outbound/cache_availability'
require_relative '../../shared/source_fingerprint'
require_relative 'cache_paths'
require_relative 'json_cache_store'
require_relative 'cache_pointer_manager'
require_relative 'epub_cache'

module Shoko
  module Adapters
    module Storage
      # Adapter for checking if a cache entry exists for a given source path.
      class CacheAvailabilityAdapter
        include Application::Ports::Outbound::CacheAvailability

        SourceState = Data.define(:path, :mtime, :size_bytes, :fingerprint)

        def initialize(cache_root: CachePaths.cache_root, store: nil, logger: nil, runtime_config: nil)
          @cache_root = cache_root
          @runtime_config = runtime_config
          @store = store || JsonCacheStore.new(cache_root: cache_root, logger: logger, runtime_config: runtime_config)
        end

        def cache_available?(path)
          source_path = path.to_s
          return false unless readable_source_path?(source_path)
          return cache_payload_for_pointer?(source_path) if Adapters::Storage::EpubCache.cache_file?(source_path)

          manifest_payload_available?(source_path)
        end

        private

        def readable_source_path?(source_path)
          !source_path.empty? && File.file?(source_path)
        end

        def cache_payload_for_pointer?(source_path)
          pointer = CachePointerManager.new(source_path).read
          sha = normalized_sha(pointer && pointer['sha256'])
          return false unless sha

          File.file?(payload_path(sha))
        end

        def manifest_payload_available?(source_path)
          rows = JsonCacheStore.manifest_rows(@cache_root, runtime_config: @runtime_config)
          return false if rows.empty?

          source_state = build_source_state(source_path)
          rows.any? { |row| payload_match?(row, source_state) }
        end

        def build_source_state(source_path)
          SourceState.new(
            path: source_path,
            mtime: File.mtime(source_path).utc,
            size_bytes: File.size(source_path),
            fingerprint: normalized_fingerprint(Shoko::Shared::SourceFingerprint.compute(source_path))
          )
        end

        def payload_match?(row, source_state)
          normalized = normalize_row(row)
          return false unless normalized
          return false unless row_matches_source?(normalized, source_state)

          sha = normalized_sha(normalized[:source_sha])
          sha ? File.file?(payload_path(sha)) : false
        end

        def row_matches_source?(row, source_state)
          row[:source_path] == source_state.path &&
            mtime_match?(row[:source_mtime], source_state.mtime) &&
            size_match?(row[:source_size_bytes], source_state.size_bytes) &&
            fingerprint_match?(row[:source_fingerprint], source_state.fingerprint)
        end

        def normalize_row(row)
          return nil unless row.is_a?(Hash)

          {
            source_path: row['source_path'].to_s,
            source_mtime: row['source_mtime'],
            source_size_bytes: row['source_size_bytes'],
            source_fingerprint: normalized_fingerprint(row['source_fingerprint']),
            source_sha: row['source_sha'].to_s,
          }
        end

        def normalized_fingerprint(value)
          str = value.to_s.strip
          str.empty? ? nil : str
        end

        def normalized_sha(value)
          str = value.to_s.strip
          str.empty? ? nil : str.downcase
        end

        def payload_path(sha)
          File.join(@cache_root, "#{sha}.json")
        end

        def fingerprint_match?(row_fingerprint, source_fingerprint)
          return true unless row_fingerprint && source_fingerprint

          row_fingerprint == source_fingerprint
        end

        def mtime_match?(raw, source_mtime)
          return true unless raw

          (raw.to_f - source_mtime.to_f).abs <= 1.0
        end

        def size_match?(raw, source_size)
          return true unless raw

          raw.to_i == source_size.to_i
        end
      end
    end
  end
end
