# frozen_string_literal: true

require_relative 'pagination_layout_resolver'
require_relative 'pagination_layout_spec'
require_relative 'pagination_cache_layout_lookup'
require_relative 'pagination_cache_state_hydrator'
require 'shoko/application/ports/outbound/app_config_store'
require 'shoko/application/ports/outbound/reader_session_store'
require 'shoko/application/ports/outbound/reader_runtime_context'

module Shoko
  module Application
    module Services
      module Pagination
        # Centralises the logic for hydrating dynamic pagination from the cache.
        #
        # This class follows hexagonal architecture principles:
        # - Config and reader state go through typed session stores
        # - Runtime sizing/display go through ReaderRuntimeContext
        class PaginationCachePreloader
          # Preload outcome with an optional cache key.
          Result = Struct.new(:status, :key)
          private_constant :Result

          # @param page_calculator [Object] Page calculator service
          # @param pagination_cache [Object] Pagination cache storage
          # @param logger [Object, nil] Optional logger
          def initialize(page_calculator:, pagination_cache:, app_config_store:, reader_session_store:,
                         reader_runtime_context:, reader_state_reader: nil, reader_pagination_store: nil,
                         logger: nil, layout_lookup: nil, state_hydrator: nil)
            @page_calculator = page_calculator
            @pagination_cache = pagination_cache
            @reader_state_reader = reader_state_reader || reader_session_store
            @logger = logger

            layout_resolver = PaginationLayoutResolver.new(
              display_capabilities: reader_runtime_context.display_capabilities,
              pagination_cache: pagination_cache
            )
            @layout_lookup = layout_lookup || PaginationCacheLayoutLookup.new(
              app_config_store: app_config_store,
              reader_state_reader: @reader_state_reader,
              reader_runtime_context: reader_runtime_context,
              pagination_cache: pagination_cache,
              layout_resolver: layout_resolver
            )
            @state_hydrator = state_hydrator || PaginationCacheStateHydrator.new(
              page_calculator: page_calculator,
              app_config_store: app_config_store,
              reader_session_store: reader_session_store,
              reader_state_reader: @reader_state_reader,
              reader_pagination_store: reader_pagination_store || @reader_state_reader
            )
          end

          # @return [Result] :hit for a current-size layout, :stale for a
          #   different-size fallback layout (hydrated for instant display, but
          #   the caller must still rebuild for the real size), :miss otherwise.
          def preload(doc, width:, height:)
            guard = guard_preload(doc)
            return guard if guard

            lookup = @layout_lookup.resolve(doc: doc, width: width, height: height)
            return miss_result(lookup.miss_key) unless lookup.layout

            hydrate_lookup(doc, lookup)
          rescue Shoko::Error => e
            log_failure(e)
            Result.new(status: :error)
          end

          private

          def guard_preload(doc)
            return Result.new(status: :invalid) unless doc
            return Result.new(status: :unavailable) unless @layout_lookup.dynamic_mode?

            Result.new(status: :no_calculator) unless @page_calculator
          end

          def load_cached_pages(doc, key)
            cached_pages = @pagination_cache.load_for_document(doc, key)
            cached_pages if cached_pages&.any?
          end

          def hydrate_lookup(doc, lookup)
            cached_pages = load_cached_pages(doc, lookup.layout.cache_key)
            return miss_result(lookup.layout.cache_key) unless cached_pages

            @state_hydrator.hydrate(
              doc: doc,
              cached_pages: cached_pages,
              dimensions: lookup.dimensions,
              layout: lookup.layout
            )
            Result.new(status: hit_status(lookup), key: lookup.layout.cache_key)
          end

          # A fallback layout paginated for other dimensions keeps the reader
          # instantly readable, but it is not the current size's page map.
          def hit_status(lookup)
            layout = lookup.layout
            current = lookup.dimensions
            layout.width == current.width && layout.height == current.height ? :hit : :stale
          end

          def miss_result(key)
            Result.new(status: :miss, key: key)
          end

          def log_failure(error)
            @logger&.debug('PaginationCachePreloader: failed', error: error.message)
          end
        end
      end
    end
  end
end
