# frozen_string_literal: true

require_relative '../../../core/ports/outbound/app_config_store'
require_relative '../../../core/ports/outbound/reader_session_store'
require_relative '../../../core/ports/outbound/reader_runtime_context'

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
          # Requested terminal dimensions (before defaults are applied).
          Dimensions = Struct.new(:width, :height)
          # Layout metadata used for pagination cache lookups.
          LayoutSpec = Struct.new(:key, :width, :height, :view_mode, :line_spacing, :kitty_images, :layout_variant)
          private_constant :Result, :Dimensions, :LayoutSpec

          # @param page_calculator [Object] Page calculator service
          # @param pagination_cache [Object] Pagination cache storage
          # @param logger [Object, nil] Optional logger
          def initialize(page_calculator:, pagination_cache:, app_config_store:, reader_session_store:,
                         reader_runtime_context:, reader_state_reader: nil, reader_pagination_store: nil,
                         logger: nil)
            @page_calculator = page_calculator
            @pagination_cache = pagination_cache
            @app_config_store = app_config_store
            @reader_session_store = reader_session_store
            @reader_state_reader = reader_state_reader || reader_session_store
            @reader_pagination_store = reader_pagination_store || @reader_state_reader
            @reader_runtime_context = reader_runtime_context
            @logger = logger
          end

          def preload(doc, width:, height:)
            guard = guard_preload(doc)
            return guard if guard

            dimensions = resolve_dimensions(Dimensions.new(width: width, height: height))
            layout, miss_key = resolve_layout(doc, dimensions)
            return Result.new(status: :miss, key: miss_key) unless layout

            apply_layout_config(layout)
            cached_pages = load_cached_pages(doc, layout.key)
            return Result.new(status: :miss, key: layout.key) unless cached_pages

            hydrate_from_cache(doc, cached_pages, dimensions, layout)
            Result.new(status: :hit, key: layout.key)
          rescue Shoko::Error => e
            log_failure(e)
            Result.new(status: :error)
          end

          private

          attr_reader :page_calculator, :pagination_cache, :app_config_store, :reader_session_store,
                      :reader_state_reader, :reader_pagination_store,
                      :reader_runtime_context, :logger

          def guard_preload(doc)
            return Result.new(status: :invalid) unless doc
            return Result.new(status: :unavailable) unless dynamic_mode?

            Result.new(status: :no_calculator) unless page_calculator
          end

          def resolve_dimensions(requested)
            size = reader_runtime_context.terminal_size
            width = requested.width || size.width || 80
            height = requested.height || size.height || 24
            Dimensions.new(width: width, height: height)
          end

          def resolve_layout(doc, dimensions)
            layout = build_layout_spec(dimensions)
            miss_key = layout.key
            return [layout, miss_key] if pagination_cache.exists_for_document?(doc, layout.key)

            [find_fallback_layout(doc, layout), miss_key]
          end

          def dynamic_mode?
            current_config.page_numbering_mode == :dynamic
          end

          def build_layout_spec(dimensions)
            view_mode = current_view_mode
            line_spacing = current_line_spacing
            kitty_images = reader_runtime_context.display_capabilities.kitty_images_enabled?(current_config)
            layout_variant = current_layout_variant
            key = pagination_cache.layout_key(
              dimensions.width,
              dimensions.height,
              view_mode,
              line_spacing,
              kitty_images: kitty_images,
              layout_variant: layout_variant
            )
            LayoutSpec.new(
              key: key,
              width: dimensions.width,
              height: dimensions.height,
              view_mode: view_mode,
              line_spacing: line_spacing,
              kitty_images: kitty_images,
              layout_variant: layout_variant
            )
          end

          def apply_layout_config(layout)
            @reader_pagination_store.save(current_pagination.with(last_width: layout.width, last_height: layout.height))
            update_config(layout)
          end

          def update_config(layout)
            updates = {}
            updates[:view_mode] = layout.view_mode if layout.view_mode
            updates[:line_spacing] = layout.line_spacing if layout.line_spacing
            return if updates.empty?

            @app_config_store.save(current_config.with(**updates))
          end

          def load_cached_pages(doc, key)
            cached_pages = pagination_cache.load_for_document(doc, key)
            cached_pages if cached_pages&.any?
          end

          def hydrate_from_cache(doc, cached_pages, dimensions, layout)
            payload = page_calculator.hydrate_from_cache(
              cached_pages,
              doc: doc,
              width: dimensions.width,
              height: dimensions.height,
              sidebar_visible: layout&.layout_variant == :sidebar
            )
            @reader_pagination_store.save(current_pagination.with(**payload)) if payload
            restore = page_calculator.apply_pending_precise_restore!(reader_state_reader)
            return unless restore

            updates = {}
            if restore.key?(:current_page_index) && !restore[:current_page_index].nil?
              updates[:current_page_index] = restore[:current_page_index]
            end
            updates[:pending_progress] = nil if restore[:clear_pending_progress]
            @reader_session_store.save(current_reader.with(**updates)) unless updates.empty?
          end

          def log_failure(error)
            logger&.debug('PaginationCachePreloader: failed', error: error.message)
          end

          def find_fallback_layout(doc, layout)
            keys = pagination_cache.layout_keys_for_document(doc)
            return nil if keys.empty?

            preferred = preferred_key(keys, layout)
            return nil unless preferred

            layout_from_key(preferred)
          end

          def preferred_key(keys, layout)
            keys.find { |candidate| layout_key_matches?(candidate, layout) }
          end

          def layout_key_matches?(candidate, layout)
            parsed = pagination_cache.parse_layout_key(candidate)
            return false unless parsed

            parsed[:view_mode] == layout.view_mode &&
              parsed[:line_spacing] == layout.line_spacing &&
              parsed[:kitty_images] == layout.kitty_images &&
              parsed[:layout_variant] == layout.layout_variant
          end

          def layout_from_key(key)
            parsed = pagination_cache.parse_layout_key(key)
            return nil unless parsed

            LayoutSpec.new(
              key: key,
              width: parsed[:width],
              height: parsed[:height],
              view_mode: parsed[:view_mode],
              line_spacing: parsed[:line_spacing],
              kitty_images: parsed[:kitty_images],
              layout_variant: parsed[:layout_variant]
            )
          end

          def current_view_mode
            current_config.view_mode
          end

          def current_line_spacing
            current_config.line_spacing
          end

          def current_layout_variant
            return :base unless dynamic_mode?

            reader_state_reader.sidebar_visible? ? :sidebar : :base
          end

          def current_config
            app_config_store.load
          end

          def current_reader
            reader_session_store.load
          end

          def current_pagination
            reader_pagination_store.load
          end
        end
      end
    end
  end
end
