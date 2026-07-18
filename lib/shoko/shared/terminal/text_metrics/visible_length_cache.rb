# frozen_string_literal: true

require_relative 'runtime_controls'

module Shoko
  module Shared
    module Terminal
      module TextMetrics
        # Per-thread memo of visible display widths for short strings.
        class VisibleLengthCache
          LIMIT = 20_000
          CACHEABLE_BYTES = 256
          STORE_KEY = :shoko_visible_length_cache

          def initialize(controls:)
            @controls = controls
          end

          def fetch(source)
            store = store_for(source)
            return yield unless store

            cached = store[source]
            return cached unless cached.nil?

            width = yield
            write(store, source, width)
            width
          end

          def clear!
            Thread.current[STORE_KEY] = {}
          end

          private

          def store_for(source)
            return nil unless @controls.visible_length_cache_enabled?
            return nil unless source.to_s.bytesize <= CACHEABLE_BYTES

            Thread.current[STORE_KEY] ||= {}
          end

          def write(store, source, width)
            key = source.frozen? ? source : source.dup.freeze
            store[key] = width
            store.shift while store.length > LIMIT
          end
        end
      end
    end
  end
end
