# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      class BookCachePipeline
        # Finds the best manifest SHA match for a source file.
        class ManifestShaFinder
          FAST_SCAN_ENABLED_KEY = :shoko_fast_manifest_lookup_enabled

          class << self
            def with_fast_scan(enabled:)
              previous = Thread.current[FAST_SCAN_ENABLED_KEY]
              Thread.current[FAST_SCAN_ENABLED_KEY] = enabled ? true : false
              yield
            ensure
              Thread.current[FAST_SCAN_ENABLED_KEY] = previous
            end

            def fast_scan_enabled?(runtime_config:)
              override = Thread.current[FAST_SCAN_ENABLED_KEY]
              return override unless override.nil?
              return true if runtime_config.nil?

              !runtime_config.fast_manifest_lookup_disabled?
            end
          end

          def initialize(rows:, source_path:, source_mtime:, source_size_bytes:, runtime_config: nil)
            @rows = rows || []
            @wrapped_rows = nil
            @source_path = source_path
            @source_mtime = source_mtime
            @source_size_bytes = source_size_bytes
            @source_fingerprint = nil
            @source_fingerprint_loaded = false
            @runtime_config = runtime_config
          end

          def sha
            if self.class.fast_scan_enabled?(runtime_config: @runtime_config)
              fast_sha
            else
              legacy_sha
            end
          end

          private

          def legacy_sha
            best = best_match
            best&.source_sha
          end

          def best_match
            filtered_rows.max_by(&:updated_at)
          end

          def filtered_rows
            fingerprint_matches(size_matches(mtime_matches(path_matches)))
          end

          def wrapped_rows
            @wrapped_rows ||= @rows.each_with_object([]) do |row, acc|
              wrapper = ManifestRow.from(row)
              acc << wrapper if wrapper
            end
          end

          def path_matches
            wrapped_rows.select { |row| row.path_match?(@source_path) }
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

          def fast_sha
            best_sha = nil
            best_updated = -Float::INFINITY
            fingerprinted_rows_seen = false
            source_fp = nil

            @rows.each do |row|
              next unless row.is_a?(Hash)
              next unless path_match_fast?(row)
              next unless mtime_match_fast?(row)
              next unless size_match_fast?(row)

              fingerprint = fingerprint_value_fast(row)
              if fingerprint
                fingerprinted_rows_seen = true
                source_fp = fast_source_fingerprint if source_fp.nil?
                next if source_fp.empty? || source_fp != fingerprint
              end

              sha = source_sha_fast(row)
              next unless sha

              updated = updated_at_fast(row)
              next unless updated >= best_updated

              best_sha = sha
              best_updated = updated
            end

            return nil if fingerprinted_rows_seen && source_fp.to_s.empty?

            best_sha
          end

          def path_match_fast?(row)
            row['source_path'].to_s == @source_path
          end

          def mtime_match_fast?(row)
            raw_mtime = row['source_mtime']
            return false unless raw_mtime

            (raw_mtime.to_f - @source_mtime.to_f).abs <= 1.0
          end

          def size_match_fast?(row)
            raw_size = row['source_size_bytes']
            return true unless raw_size

            raw_size.to_i == @source_size_bytes.to_i
          end

          def fingerprint_value_fast(row)
            value = row['source_fingerprint'].to_s.strip
            value.empty? ? nil : value
          end

          def source_sha_fast(row)
            value = row['source_sha'].to_s.strip
            value.empty? ? nil : value
          end

          def updated_at_fast(row)
            row['updated_at'].to_f
          end

          def fast_source_fingerprint
            return @source_fingerprint if @source_fingerprint_loaded

            @source_fingerprint = Shoko::Shared::SourceFingerprint.compute(@source_path).to_s
            @source_fingerprint_loaded = true
            @source_fingerprint
          end
        end

        private_constant :ManifestShaFinder
      end
    end
  end
end
