# frozen_string_literal: true

module Shoko
  module Adapters::Storage
    class BookCachePipeline
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
    end
  end
end
