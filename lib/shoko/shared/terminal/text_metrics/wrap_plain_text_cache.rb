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
            return immutable_lines(yield) unless store

            key = immutable_key(source, width)
            if store.key?(key)
              cached = store.delete(key)
              store[key] = cached
              return cached
            end

            write(store, key, yield)
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

          def write(store, key, wrapped)
            lines = immutable_lines(wrapped)
            store[key] = lines
            store.shift while store.length > LIMIT
            lines
          end

          # Build the immutable copied key BEFORE lookup. Re-inserting a hit
          # with the caller's temporary [width, source] key would make a
          # mutable caller String part of the Hash and corrupt the memo if the
          # caller later changed it.
          def immutable_key(source, width)
            [width, source.to_s.dup.freeze].freeze
          end

          def immutable_lines(wrapped)
            wrapped.map { |line| line.to_s.dup.freeze }.freeze
          end
        end
      end
    end
  end
end
