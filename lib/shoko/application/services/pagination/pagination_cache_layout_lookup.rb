# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        # Resolves preload dimensions and cache-compatible dynamic layout metadata.
        class PaginationCacheLayoutLookup
          Dimensions = Data.define(:width, :height)
          Lookup = Data.define(:dimensions, :layout, :miss_key)

          def initialize(app_config_store:, reader_state_reader:, reader_runtime_context:, pagination_cache:,
                         layout_resolver:)
            @app_config_store = app_config_store
            @reader_state_reader = reader_state_reader
            @reader_runtime_context = reader_runtime_context
            @pagination_cache = pagination_cache
            @layout_resolver = layout_resolver
          end

          def dynamic_mode?
            current_config.page_numbering_mode == :dynamic
          end

          def resolve(doc:, width:, height:)
            dimensions = resolve_dimensions(width:, height:)
            requested_layout = @layout_resolver.resolve(
              config_reader: current_config,
              width: dimensions.width,
              height: dimensions.height,
              sidebar_visible: @reader_state_reader.sidebar_visible?
            )
            miss_key = requested_layout.cache_key
            layout = if cache_hit?(doc, requested_layout)
                       requested_layout
                     else
                       find_fallback_layout(doc, requested_layout)
                     end
            Lookup.new(dimensions: dimensions, layout: layout, miss_key: miss_key)
          end

          private

          def resolve_dimensions(width:, height:)
            size = @reader_runtime_context.terminal_size
            Dimensions.new(
              width: width || size.width || 80,
              height: height || size.height || 24
            )
          end

          def cache_hit?(doc, layout)
            return false unless @pagination_cache && layout&.cache_key

            @pagination_cache.exists_for_document?(doc, layout.cache_key)
          end

          def find_fallback_layout(doc, layout)
            return nil unless @pagination_cache

            preferred = @pagination_cache.layout_keys_for_document(doc).find do |candidate|
              @layout_resolver.matches_cache_key?(candidate, layout)
            end
            return nil unless preferred

            @layout_resolver.from_cache_key(preferred)
          end

          def current_config
            @app_config_store.load
          end
        end
      end
    end
  end
end
