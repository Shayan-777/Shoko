# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Reading
          # Cache helpers for line composition results.
          module LineContentComposerCacheSupport
            private

            def compose_cache_key(line, width, options)
              return nil unless self.class.compose_cache_enabled?

              cache_key_for(line, width, options) << Shoko::Adapters::Ui::Components::RenderStyle.palette.object_id
            end

            def cache_key_for(line, width, options)
              return display_line_cache_key(line, width, options) if display_line?(line)

              plain_line_cache_key(line, width, options)
            end

            def display_line_cache_key(line, width, options)
              metadata = line.metadata || {}
              text = line.text.to_s
              [
                :display_line,
                line.object_id,
                line.segments.object_id,
                text.hash,
                text.bytesize,
                canonical_block_type(metadata),
                width,
                options.highlight_quotes,
                options.highlight_keywords,
                options.hover_signature,
              ]
            end

            def plain_line_cache_key(line, width, options)
              text = line.to_s
              [
                :plain_line,
                text.hash,
                text.bytesize,
                width,
                options.highlight_quotes,
                options.highlight_keywords,
              ]
            end

            def fetch_cached_compose(key)
              return nil unless key && self.class.compose_cache_enabled?

              compose_cache_store[key]
            end

            def cache_compose_result(key, result)
              return result unless key && self.class.compose_cache_enabled?

              frozen_result = freeze_compose_result(result)
              track_compose_cache_key(key)
              compose_cache_store[key] = frozen_result
              frozen_result
            end

            def freeze_compose_result(result)
              plain, styled = result
              [plain.to_s.freeze, styled.to_s.freeze].freeze
            end

            def track_compose_cache_key(key)
              return if compose_cache_store.key?(key)

              compose_cache_order << key
              prune_compose_cache if compose_cache_order.length > self.class::COMPOSE_CACHE_LIMIT
            end

            def prune_compose_cache
              oldest = compose_cache_order.shift
              compose_cache_store.delete(oldest)
            end

            def compose_cache_store
              Thread.current[self.class::COMPOSE_CACHE_KEY] ||= {}
            end

            def compose_cache_order
              Thread.current[self.class::COMPOSE_CACHE_ORDER_KEY] ||= []
            end
          end
        end
      end
    end
  end
end
