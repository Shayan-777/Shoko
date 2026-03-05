# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      # Layout storage helpers for `JsonCacheStore`.
      class JsonCacheStore
        private

        def layouts_dir(sha)
          File.join(@cache_root, 'layouts', normalize_sha!(sha))
        end

        def layout_file(sha, key)
          File.join(layouts_dir(sha), "#{normalize_layout_key!(key)}.json")
        end

        def layout_key_for_entry(entry)
          return nil unless entry.end_with?('.json')

          key = entry.delete_suffix('.json')
          layout_key_valid?(key) ? key : nil
        end

        def read_layout_payload(dir, entry, sha:, key:)
          JSON.parse(File.read(File.join(dir, entry)))
        rescue Shoko::Error => e
          @logger&.debug('JsonCacheStore: layout parse failed', sha: sha.to_s, key: key.to_s,
                                                                error: e.message)
          nil
        end

        def write_layouts(sha, layouts_hash)
          dir = layouts_dir(sha)
          FileUtils.mkdir_p(dir)
          existing = Dir.exist?(dir) ? Dir.children(dir).select { |entry| entry.end_with?('.json') } : []

          written = []
          layouts_hash.each do |key, payload|
            normalized_key = normalize_layout_key!(key)
            file = File.join(dir, "#{normalized_key}.json")
            AtomicFileWriter.write(file, JSON.generate(payload))
            written << "#{normalized_key}.json"
          end

          stale = existing - written
          stale.each { |entry| FileUtils.rm_f(File.join(dir, entry)) }
        end

        def layout_key_valid?(key)
          normalize_layout_key!(key)
          true
        end

        def normalize_layout_key!(key)
          value = key.to_s
          raise ArgumentError, 'layout key is blank' if value.empty?
          raise ArgumentError, 'layout key too long' if value.bytesize > MAX_LAYOUT_KEY_BYTES
          raise ArgumentError, 'layout key contains null byte' if value.include?("\0")
          raise ArgumentError, 'layout key contains path separator' if value.include?('/') || value.include?('\\')
          raise ArgumentError, 'layout key has invalid characters' unless LAYOUT_KEY_PATTERN.match?(value)

          value
        end
      end
    end
  end
end
