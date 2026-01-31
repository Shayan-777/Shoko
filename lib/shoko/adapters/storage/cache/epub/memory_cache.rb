# frozen_string_literal: true

module Shoko
  module Adapters::Storage
    # In-memory caching helpers for loaded payloads + layouts.
    class EpubCache
      private

      def load_payload
        return @payload_cache if @payload_cache

        ensure_sha!
        cache_payload(load_payload_from_store(@source_sha))
      end

      def cache_payload(payload)
        return nil unless payload

        @payload_cache = payload
        @layout_cache = normalize_layout_cache(payload.layouts)
        refresh_payload_layouts!
        payload
      end

      def load_payload_from_store(sha)
        raw = fetch_raw_payload(sha)
        return nil unless raw

        ensure_pointer_from_metadata(raw.metadata_row)
        Serializer.build_payload_from_store(raw, cache_root: @cache_root, book_sha: sha)
      rescue StandardError => e
        @logger&.debug('EpubCache: failed to load cache', sha: sha.to_s, error: e.message)
        nil
      end

      def fetch_raw_payload(sha)
        return nil unless sha

        @cache_store.fetch_payload(sha)
      end

      def cache_layout!(key, payload)
        @layout_cache ||= {}
        @layout_cache[key] = deep_dup(payload)
        return unless @payload_cache

        @payload_cache.layouts ||= {}
        @payload_cache.layouts[key] = deep_dup(payload)
      end

      def update_layout_cache_from_layouts(layouts)
        @layout_cache = normalize_layout_cache(layouts)
        refresh_payload_layouts!
      end

      def refresh_payload_layouts!
        return unless @payload_cache

        @payload_cache.layouts = @layout_cache.transform_values do |value|
          deep_dup(value)
        end
      end

      def normalize_layout_cache(layouts)
        (layouts || {}).each_with_object({}) do |(key, payload), acc|
          acc[key.to_s] = deep_dup(payload)
        end
      end

      def deep_dup(obj)
        deep_dup_value(obj)
      end

      def deep_dup_value(value)
        case value
        when String
          value.dup
        when Array
          value.map { |item| deep_dup_value(item) }
        when Hash
          value.transform_values { |item| deep_dup_value(item) }
        else
          value
        end
      end

      def invalidate_and_nil
        invalidate!
        nil
      end

      def payload_valid?(payload)
        payload.is_a?(CachePayload) &&
          payload.version.to_i == CACHE_VERSION &&
          payload.book.is_a?(BookData)
      end
    end
  end
end
