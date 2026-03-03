# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      # Resource persistence helpers for `JsonCacheStore`.
      class JsonCacheStore
        private

        def resources_dir(sha)
          File.join(@cache_root, 'resources', normalize_sha!(sha))
        end

        def resource_blob_path(sha, blob_key)
          File.join(resources_dir(sha), "#{blob_key}.bin")
        end

        def hydrate_resources(sha, index_rows)
          Array(index_rows).filter_map { |row| hydrate_resource_row(sha, row) }
        end

        def hydrate_resource_row(sha, row)
          path, blob_key = resource_index_row_fields(row)
          path_string = path.to_s
          blob_key_string = blob_key.to_s
          return nil if path_string.empty? || blob_key_string.empty?

          data = File.binread(resource_blob_path(sha, blob_key_string))
          data.force_encoding(Encoding::BINARY)
          { path: path_string, data: data }
        rescue Shoko::Error
          raise
        end

        def resource_index_row_fields(row)
          return [nil, nil] unless row.is_a?(Hash)

          [row['path'] || row[:path], row['blob'] || row[:blob]]
        end

        def persist_resources(sha, resources_rows)
          resources_rows = Array(resources_rows)
          return [[], 0] if resources_rows.empty?

          FileUtils.mkdir_p(resources_dir(sha))

          rows = []
          total_bytes = 0
          resources_rows.each do |row|
            persisted = persist_resource_row(sha, row)
            next unless persisted

            rows << persisted[:index_row]
            total_bytes += persisted[:bytesize]
          end

          [rows, total_bytes]
        end

        def persist_resource_row(sha, row)
          path, data = resource_row_fields(row)
          path_string = path.to_s
          return nil if path_string.empty?

          bytes = String(data).dup
          bytes.force_encoding(Encoding::BINARY)
          blob_key = Digest::SHA256.hexdigest(path_string)

          AtomicFileWriter.write(resource_blob_path(sha, blob_key), bytes, binary: true)

          bytesize = bytes.bytesize
          {
            bytesize: bytesize,
            index_row: { 'path' => path_string, 'blob' => blob_key, 'bytesize' => bytesize },
          }
        end

        def resource_row_fields(row)
          return [nil, nil] unless row.is_a?(Hash)

          [row[:path] || row['path'], row[:data] || row['data']]
        end
      end
    end
  end
end
