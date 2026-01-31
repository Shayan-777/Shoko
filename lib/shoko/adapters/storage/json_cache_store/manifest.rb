# frozen_string_literal: true

module Shoko
  module Adapters::Storage
    # Manifest helpers for `JsonCacheStore` (cache listing).
    class JsonCacheStore
      private

      def manifest_path
        File.join(@cache_root, MANIFEST_FILENAME)
      end

      def update_manifest(metadata_row, cache_size_bytes:)
        row = metadata_row.merge('cache_size_bytes' => cache_size_bytes.to_i)
        manifest = self.class.manifest_rows(@cache_root)
        manifest.reject! { |entry| entry['source_sha'] == row['source_sha'] }
        manifest << row
        AtomicFileWriter.write(manifest_path, JSON.generate(manifest))
      rescue StandardError => e
        @logger&.debug('JsonCacheStore: manifest write failed', error: e.message)
      end

      def remove_from_manifest(sha)
        manifest = self.class.manifest_rows(@cache_root)
        manifest.reject! { |entry| entry['source_sha'] == sha }
        AtomicFileWriter.write(manifest_path, JSON.generate(manifest))
      rescue StandardError
        nil
      end

      def self.read_manifest_file(path)
        return [] unless File.file?(path)

        data = JSON.parse(File.read(path))
        data.is_a?(Array) ? data : []
      rescue StandardError
        []
      end
      private_class_method :read_manifest_file
    end
  end
end
