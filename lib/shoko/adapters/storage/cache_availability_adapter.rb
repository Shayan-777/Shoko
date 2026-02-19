# frozen_string_literal: true

require_relative '../../core/ports/cache_availability'
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
        include Core::Ports::CacheAvailability

        def initialize(cache_root: CachePaths.cache_root, store: nil, logger: nil, runtime_config: nil)
          @cache_root = cache_root
          @runtime_config = runtime_config
          @store = store || JsonCacheStore.new(
            cache_root: cache_root,
            logger: logger,
            runtime_config: runtime_config
          )
        end

        def cache_available?(path)
          source_path = path.to_s
          return false if source_path.empty?
          return false unless File.file?(source_path)

          if Adapters::Storage::EpubCache.cache_file?(source_path)
            pointer = CachePointerManager.new(source_path).read
            sha = pointer && pointer['sha256']
            return false if sha.to_s.strip.empty?

            payload_path = File.join(@cache_root, "#{sha.downcase}.json")
            return File.file?(payload_path)
          end

          rows = JsonCacheStore.manifest_rows(@cache_root, runtime_config: @runtime_config)
          return false if rows.empty?

          fingerprint = Shoko::Shared::SourceFingerprint.compute(source_path).to_s
          fingerprint = nil if fingerprint.empty?
          source_mtime = File.mtime(source_path).utc
          source_size = File.size(source_path)

          rows.any? do |row|
            row = normalize_row(row)
            next false unless row

            next false unless row[:source_path] == source_path
            next false unless mtime_match?(row[:source_mtime], source_mtime)
            next false unless size_match?(row[:source_size_bytes], source_size)
            next false if row[:source_fingerprint] && fingerprint && row[:source_fingerprint] != fingerprint

            sha = row[:source_sha]
            next false if sha.to_s.strip.empty?

            payload_path = File.join(@cache_root, "#{sha.downcase}.json")
            File.file?(payload_path)
          end
        rescue StandardError
          false
        end

        private

        def normalize_row(row)
          return nil unless row.is_a?(Hash)

          {
            source_path: row['source_path'].to_s,
            source_mtime: row['source_mtime'],
            source_size_bytes: row['source_size_bytes'],
            source_fingerprint: normalize_fingerprint(row['source_fingerprint']),
            source_sha: row['source_sha'].to_s,
          }
        end

        def normalize_fingerprint(value)
          str = value.to_s.strip
          str.empty? ? nil : str
        end

        def mtime_match?(raw, source_mtime)
          return true unless raw

          (raw.to_f - source_mtime.to_f).abs <= 1.0
        rescue StandardError
          false
        end

        def size_match?(raw, source_size)
          return true unless raw

          raw.to_i == source_size.to_i
        rescue StandardError
          false
        end
      end
    end
  end
end
