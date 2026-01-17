# frozen_string_literal: true

require_relative '../pagination'
require_relative '../../../adapters/output/kitty/kitty_graphics'
require_relative '../../ports/config_reader'
require_relative '../../ports/state_writer'

module Shoko
  module Core
    module Services
      module Pagination
        # Centralises the logic for hydrating dynamic pagination from the cache.
        #
        # This class follows hexagonal architecture principles:
        # - Config reading goes through ConfigReader port
        # - State writing goes through StateWriter port
        class PaginationCachePreloader
          # Preload outcome with an optional cache key.
          Result = Struct.new(:status, :key, keyword_init: true)
          # Requested terminal dimensions (before defaults are applied).
          Dimensions = Struct.new(:width, :height, keyword_init: true)
          # Layout metadata used for pagination cache lookups.
          LayoutSpec = Struct.new(:key, :width, :height, :view_mode, :line_spacing, :kitty_images, keyword_init: true)
          private_constant :Result, :Dimensions, :LayoutSpec

          # @param state [Object] State store for reading state
          # @param page_calculator [Object] Page calculator service
          # @param pagination_cache [Object] Pagination cache storage
          # @param config_reader [Core::Ports::ConfigReader] Port for reading config
          # @param state_writer [Core::Ports::StateWriter] Port for writing state
          def initialize(state:, page_calculator:, pagination_cache:, config_reader:, state_writer: nil)
            @state = state
            @page_calculator = page_calculator
            @pagination_cache = pagination_cache
            @config_reader = config_reader
            @state_writer = state_writer
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

            hydrate_from_cache(cached_pages, dimensions)
            Result.new(status: :hit, key: layout.key)
          rescue StandardError => e
            log_failure(e)
            Result.new(status: :error)
          end

          private

          attr_reader :state, :page_calculator, :pagination_cache, :config_reader, :state_writer

          def guard_preload(doc)
            return Result.new(status: :invalid) unless doc
            return Result.new(status: :unavailable) unless dynamic_mode?

            Result.new(status: :no_calculator) unless page_calculator
          end

          def resolve_dimensions(requested)
            width = requested.width || state.get(%i[ui terminal_width]) || 80
            height = requested.height || state.get(%i[ui terminal_height]) || 24
            Dimensions.new(width: width, height: height)
          end

          def resolve_layout(doc, dimensions)
            layout = build_layout_spec(dimensions)
            miss_key = layout.key
            return [layout, miss_key] if pagination_cache.exists_for_document?(doc, layout.key)

            [find_fallback_layout(doc, layout), miss_key]
          end

          def dynamic_mode?
            config_reader.page_numbering_mode == :dynamic
          end

          def build_layout_spec(dimensions)
            view_mode = current_view_mode
            line_spacing = current_line_spacing
            kitty_images = Shoko::Adapters::Output::Kitty::KittyGraphics.enabled_for?(state)
            key = pagination_cache.layout_key(
              dimensions.width,
              dimensions.height,
              view_mode,
              line_spacing,
              kitty_images: kitty_images
            )
            LayoutSpec.new(
              key: key,
              width: dimensions.width,
              height: dimensions.height,
              view_mode: view_mode,
              line_spacing: line_spacing,
              kitty_images: kitty_images
            )
          end

          def apply_layout_config(layout)
            state.apply_terminal_dimensions(layout.width, layout.height)
            update_config(layout)
          end

          def update_config(layout)
            updates = {}
            updates[%i[config view_mode]] = layout.view_mode if layout.view_mode
            updates[%i[config line_spacing]] = layout.line_spacing if layout.line_spacing
            state.update(updates) unless updates.empty?
          end

          def load_cached_pages(doc, key)
            cached_pages = pagination_cache.load_for_document(doc, key)
            cached_pages if cached_pages&.any?
          end

          def hydrate_from_cache(cached_pages, dimensions)
            page_calculator.hydrate_from_cache(
              cached_pages,
              state_writer: state_writer,
              width: dimensions.width,
              height: dimensions.height
            )
            page_calculator.apply_pending_precise_restore!(state, state_writer: state_writer)
          end

          def log_failure(error)
            logger = begin
              state.resolve(:logger)
            rescue StandardError
              nil
            end
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
              parsed[:kitty_images] == layout.kitty_images
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
              kitty_images: parsed[:kitty_images]
            )
          end

          def current_view_mode
            config_reader.view_mode
          end

          def current_line_spacing
            config_reader.line_spacing
          end
        end
      end
    end
  end
end
