# frozen_string_literal: true

require_relative 'runtime_controls'

module Shoko
  module Shared
    module Terminal
      module TextMetrics
        # Per-thread LRU memo of plain-text wraps keyed by [width, source].
        # True LRU: hits reinsert the key (Ruby hashes preserve insertion
        # order), so recently used entries outlive older untouched ones.
        # Both hits and misses return the frozen cached value, so callers
        # see one consistent (immutable) contract regardless of cache state.
        class WrapPlainTextCache
          LIMIT = 2_000
          CACHEABLE_BYTES = 2_048
          STORE_KEY = :shoko_wrap_plain_text_cache

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
            cached = store.delete(key)
            return store[key] = cached if cached

            write(store, source, width, yield)
          end

          def clear!
            Thread.current[STORE_KEY] = {}
          end

          private

          def store_for(source)
            return nil unless @controls.wrap_plain_text_cache_enabled?
            return nil unless source.to_s.bytesize <= CACHEABLE_BYTES

            Thread.current[STORE_KEY] ||= {}
          end

          def write(store, source, width, wrapped)
            key_source = source.frozen? ? source : source.dup.freeze
            key = [width, key_source].freeze
            frozen = wrapped.map { |line| line.frozen? ? line : line.dup.freeze }.freeze

            store[key] = frozen
            store.shift while store.length > LIMIT
            frozen
          end
        end
      end
    end
  end
end
