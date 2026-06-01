# frozen_string_literal: true

module Shoko
  module Shared
    module Terminal
      module TextMetrics
        # Thread-local cache helpers for visible-length and plain-text wrapping.
        module Caching
          private

          def cached_visible_length(source)
            cache = visible_length_cache_for(source)
            return yield unless cache

            cached = cache[source]
            return cached unless cached.nil?

            width = yield
            cache_visible_length(cache, source, width)
            width
          end

          def cached_wrap_plain_text(source, width_i)
            cache = wrap_plain_text_cache_for(source)
            return yield unless cache

            key = [width_i, source]
            cached = cache[key]
            return cached unless cached.nil?

            wrapped = yield
            cache_wrap_plain_text(cache, source, width_i, wrapped)
            wrapped
          end

          def visible_length_cache_for(source)
            return nil unless visible_length_cache_enabled?
            return nil unless cacheable_visible_length_input?(source)

            Thread.current[VISIBLE_LENGTH_CACHE_KEY] ||= {}
          end

          def cacheable_visible_length_input?(source)
            source.to_s.bytesize <= VISIBLE_LENGTH_CACHEABLE_BYTES
          end

          def cache_visible_length(cache, source, width)
            key = source.frozen? ? source : source.dup.freeze
            cache[key] = width
            cache.shift while cache.length > VISIBLE_LENGTH_CACHE_LIMIT
          end

          def wrap_plain_text_cache_for(source)
            return nil unless wrap_plain_text_cache_enabled?
            return nil unless cacheable_wrap_plain_text_input?(source)

            Thread.current[WRAP_PLAIN_TEXT_CACHE_KEY] ||= {}
          end

          def cacheable_wrap_plain_text_input?(source)
            source.to_s.bytesize <= WRAP_PLAIN_TEXT_CACHEABLE_BYTES
          end

          def cache_wrap_plain_text(cache, source, width_i, wrapped)
            key_source = source.frozen? ? source : source.dup.freeze
            key = [width_i, key_source]
            order = Thread.current[WRAP_PLAIN_TEXT_CACHE_ORDER_KEY] ||= []

            unless cache.key?(key)
              order << key
              while order.length > WRAP_PLAIN_TEXT_CACHE_LIMIT
                oldest = order.shift
                cache.delete(oldest)
              end
            end

            cache[key] = wrapped.map { |line| line.frozen? ? line : line.dup.freeze }.freeze
          end
        end
      end
    end
  end
end
