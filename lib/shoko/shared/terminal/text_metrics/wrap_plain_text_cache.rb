# frozen_string_literal: true

require_relative 'runtime_controls'

module Shoko
  module Shared
    module Terminal
      module TextMetrics
        # Per-thread LRU memo of plain-text wraps keyed by [width, source].
        class WrapPlainTextCache
          LIMIT = 2_000
          CACHEABLE_BYTES = 2_048
          STORE_KEY = :shoko_wrap_plain_text_cache
          ORDER_KEY = :shoko_wrap_plain_text_cache_order

          def initialize(controls:)
            @controls = controls
          end

          # Named `lookup` (not `fetch`) deliberately: RuboCop's
          # Lint/UselessDefaultValueArgument autocorrects two-argument
          # `fetch(a, b) { }` calls as if they were Hash#fetch and silently
          # drops the second argument.
          def lookup(source, width)
            store = store_for(source)
            return yield unless store

            key = [width, source]
            cached = store[key]
            return cached unless cached.nil?

            wrapped = yield
            write(store, source, width, wrapped)
            wrapped
          end

          def clear!
            Thread.current[STORE_KEY] = {}
            Thread.current[ORDER_KEY] = []
          end

          private

          def store_for(source)
            return nil unless @controls.wrap_plain_text_cache_enabled?
            return nil unless source.to_s.bytesize <= CACHEABLE_BYTES

            Thread.current[STORE_KEY] ||= {}
          end

          def write(store, source, width, wrapped)
            key_source = source.frozen? ? source : source.dup.freeze
            key = [width, key_source]
            order = Thread.current[ORDER_KEY] ||= []

            unless store.key?(key)
              order << key
              while order.length > LIMIT
                oldest = order.shift
                store.delete(oldest)
              end
            end

            store[key] = wrapped.map { |line| line.frozen? ? line : line.dup.freeze }.freeze
          end
        end
      end
    end
  end
end
