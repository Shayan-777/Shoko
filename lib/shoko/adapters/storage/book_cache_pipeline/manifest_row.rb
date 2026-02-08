# frozen_string_literal: true

module Shoko
  module Adapters::Storage
    class BookCachePipeline
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
    end
  end
end
