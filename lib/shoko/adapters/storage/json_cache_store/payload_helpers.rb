# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      # Payload IO + normalization helpers for `JsonCacheStore`.
      class JsonCacheStore
        private

        def payload_path(sha)
          File.join(@cache_root, "#{normalize_sha!(sha)}.json")
        end

        def load_payload_data(sha)
          path = payload_path(sha)
          return nil unless File.file?(path)

          data = JSON.parse(File.read(path))
          valid_payload_file?(data) ? data : nil
        end

        def valid_payload_file?(data)
          return false unless data.is_a?(Hash)
          return false unless payload_header_valid?(data)

          metadata_row = data['metadata_row']
          return false unless metadata_row.is_a?(Hash)
          return false unless payload_metadata_valid?(metadata_row)
          return false unless payload_collections_valid?(data)

          true
        rescue Shoko::Error
          raise
        end

        def payload_header_valid?(data)
          data['format'] == FORMAT &&
            data['format_version'].to_i == FORMAT_VERSION &&
            data['engine'].to_s == ENGINE
        end

        def payload_metadata_valid?(metadata_row)
          CHAPTERS_GENERATION_PATTERN.match?(metadata_row['chapters_generation'].to_s) &&
            metadata_row['chapters_format_version'].to_i == CHAPTERS_FORMAT_VERSION
        end

        def payload_collections_valid?(data)
          data['chapters'].is_a?(Array) && data['resources'].is_a?(Array)
        end

        def build_metadata_row(serialized_book, normalized_sha, source_path:, source_mtime:, generated_at:)
          now = Time.now.utc.to_f
          stringify_keys(serialized_book).merge(
            'source_sha' => normalized_sha,
            'source_path' => source_path,
            'source_mtime' => source_mtime&.to_f,
            'source_size_bytes' => safe_file_size(source_path),
            'source_fingerprint' => Shoko::Shared::SourceFingerprint.compute(source_path),
            'generated_at' => generated_at&.to_f,
            'created_at' => now,
            'updated_at' => now,
            'engine' => ENGINE
          )
        end

        def payload_hash(metadata_row, chapter_generation, indexes)
          chapters_index = indexes.fetch(:chapters)
          resources_index = indexes.fetch(:resources)
          metadata_row['chapters_generation'] = chapter_generation
          metadata_row['chapters_format_version'] = CHAPTERS_FORMAT_VERSION

          {
            'format' => FORMAT,
            'format_version' => FORMAT_VERSION,
            'engine' => ENGINE,
            'metadata_row' => metadata_row,
            'chapters' => chapters_index,
            'resources' => resources_index,
          }
        end

        def write_payload_file(sha, payload)
          AtomicFileWriter.write(payload_path(sha), JSON.generate(payload))
        end

        def post_write_housekeeping(sha, metadata_row, chapter_generation, cache_size_bytes, serialized_layouts:)
          write_layouts(sha, serialized_layouts)
          update_manifest(metadata_row, cache_size_bytes: cache_size_bytes)
          cleanup_old_chapter_generations(sha, keep: chapter_generation)
        end

        def stringify_keys(hash)
          (hash || {}).transform_keys(&:to_s)
        rescue Shoko::Error
          hash || {}
        end

        def normalize_sha!(sha)
          value = sha.to_s.strip
          raise ArgumentError, 'sha is blank' if value.empty?
          raise ArgumentError, 'sha must be a 64-char hex digest' unless SHA256_HEX_PATTERN.match?(value)

          value.downcase
        end

        def safe_file_size(path)
          return nil if path.nil? || path.to_s.empty?

          File.size(path)
        rescue Shoko::Error
          raise
        end
      end
    end
  end
end
