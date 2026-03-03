# frozen_string_literal: true

require_relative '../../../core/ports/outbound/config_reader'

require_relative '../../../core/ports/outbound/reader_navigation_reader'

require_relative '../../../core/ports/outbound/pagination_state_writer'

require_relative '../../../core/ports/outbound/reader_state_writer'

require_relative '../../../core/ports/outbound/ui_state_reader'

require_relative '../../../core/ports/outbound/sidebar_state_reader'


module Shoko
  module Application
    module Services
      module Pagination
        # Centralises the logic for hydrating dynamic pagination from the cache.
        #
        # This class follows hexagonal architecture principles:
        # - Config reading goes through ConfigReader port
        # - Reader state reading goes through ReaderNavigationReader port
        # - UI state reading goes through UIStateReader port
        # - Pagination writes go through PaginationStateWriter port
        # - Config and terminal writes go through ReaderStateWriter port
        # - All dependencies must be injected (no fallback instantiation)
        class PaginationCachePreloader
          # Preload outcome with an optional cache key.
          Result = Struct.new(:status, :key, keyword_init: true)
          # Requested terminal dimensions (before defaults are applied).
          Dimensions = Struct.new(:width, :height, keyword_init: true)
          # Layout metadata used for pagination cache lookups.
          LayoutSpec = Struct.new(:key, :width, :height, :view_mode, :line_spacing, :kitty_images, :layout_variant,
                                  keyword_init: true)
          private_constant :Result, :Dimensions, :LayoutSpec

          # @param page_calculator [Object] Page calculator service
          # @param pagination_cache [Object] Pagination cache storage
          # @param config_reader [Core::Ports::Outbound::ConfigReader] Port for reading config
          # @param reader_state_reader [Core::Ports::Outbound::ReaderNavigationReader] Port for reading reader state
          # @param pagination_state_writer [Core::Ports::Outbound::PaginationStateWriter] Port for writing pagination state
          # @param reader_state_writer [Core::Ports::Outbound::ReaderStateWriter] Port for config/terminal writes
          # @param display_capabilities [Core::Ports::Outbound::DisplayCapabilities] Display capability adapter (required)
          # @param ui_state_reader [Core::Ports::Outbound::UiStateReader] Port for reading UI state
          # @param sidebar_state_reader [Core::Ports::Outbound::SidebarStateReader] Port for sidebar visibility
          # @param logger [Object, nil] Optional logger
          def initialize(page_calculator:, pagination_cache:, config_reader:, reader_state_reader:,
                         pagination_state_writer:, reader_state_writer:,
                         display_capabilities:, ui_state_reader:, sidebar_state_reader:,
                         logger: nil)
            @page_calculator = page_calculator
            @pagination_cache = pagination_cache
            @config_reader = config_reader
            @reader_state_reader = reader_state_reader
            @pagination_state_writer = pagination_state_writer
            @reader_state_writer = reader_state_writer
            @display_capabilities = display_capabilities
            @ui_state_reader = ui_state_reader
            @sidebar_state_reader = sidebar_state_reader
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

            hydrate_from_cache(cached_pages, dimensions, layout)
            Result.new(status: :hit, key: layout.key)
          rescue Shoko::Error => e
            log_failure(e)
            Result.new(status: :error)
          end

          private

          attr_reader :page_calculator, :pagination_cache, :config_reader, :reader_state_reader,
                      :pagination_state_writer, :reader_state_writer, :display_capabilities, :ui_state_reader,
                      :sidebar_state_reader, :logger

          def guard_preload(doc)
            return Result.new(status: :invalid) unless doc
            return Result.new(status: :unavailable) unless dynamic_mode?

            Result.new(status: :no_calculator) unless page_calculator
          end

          def resolve_dimensions(requested)
            width = requested.width || ui_state_reader&.terminal_width || 80
            height = requested.height || ui_state_reader&.terminal_height || 24
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
            kitty_images = display_capabilities.kitty_images_enabled?(config_reader)
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
            reader_state_writer.update_terminal_size(layout.width, layout.height)
            update_config(layout)
          end

          def update_config(layout)
            updates = {}
            updates[:view_mode] = layout.view_mode if layout.view_mode
            updates[:line_spacing] = layout.line_spacing if layout.line_spacing
            reader_state_writer.update_config(updates) unless updates.empty?
          end

          def load_cached_pages(doc, key)
            cached_pages = pagination_cache.load_for_document(doc, key)
            cached_pages if cached_pages&.any?
          end

          def hydrate_from_cache(cached_pages, dimensions, layout)
            payload = page_calculator.hydrate_from_cache(
              cached_pages,
              width: dimensions.width,
              height: dimensions.height,
              sidebar_visible: layout&.layout_variant == :sidebar
            )
            pagination_state_writer.update_pagination_state(payload) if payload
            restore = page_calculator.apply_pending_precise_restore!(reader_state_reader)
            return unless restore

            index = restore[:current_page_index]
            pagination_state_writer.update_page(current_page_index: index) if index
            pagination_state_writer.update_selections(pending_progress: nil) if restore[:clear_pending_progress]
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
            config_reader.view_mode
          end

          def current_line_spacing
            config_reader.line_spacing
          end

          def current_layout_variant
            return :base unless dynamic_mode?

            sidebar_state_reader&.sidebar_visible? == true ? :sidebar : :base
          rescue Shoko::Error
            :base
          end
        end
      end
    end
  end
end
