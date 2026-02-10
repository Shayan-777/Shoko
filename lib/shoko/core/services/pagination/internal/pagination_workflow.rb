# frozen_string_literal: true

require_relative '../../pagination'

module Shoko
  module Core
    module Services
      module Pagination
        module Internal
          # Encapsulates pagination building, caching, and layout concerns so the
          # main PageCalculatorService remains focused on high-level orchestration.
          # Uses hexagonal ports for reading state - no direct state_store access.
          class PaginationWorkflow
            Result = Struct.new(:pages, :cached, keyword_init: true)

            # @param metrics_calculator [Object] Layout metrics calculator
            # @param pagination_cache [Object, nil] Pagination cache storage
            # @param display_capabilities [Core::Ports::DisplayCapabilities] Display capability adapter (required)
            # @param instrumentation [Core::Ports::Instrumentation] Instrumentation adapter (required)
            # @param text_metrics [Core::Ports::TextMetrics] Text metrics adapter (required)
            # @param config_reader [Core::Ports::ConfigReader] Port for reading config (required)
            # @param wrapping_service [Object, nil] Optional wrapping service
            # @param formatting_service [Object, nil] Optional formatting service
            def initialize(metrics_calculator:, display_capabilities:, instrumentation:, text_metrics:,
                           config_reader:, pagination_cache: nil, wrapping_service: nil, formatting_service: nil)
              @metrics_calculator = metrics_calculator
              @pagination_cache = pagination_cache
              @display_capabilities = display_capabilities
              @instrumentation = instrumentation
              @text_metrics = text_metrics
              @config_reader = config_reader
              @wrapping_service = wrapping_service
              @formatting_service = formatting_service
            end

            def build_dynamic(doc:, width:, height:, sidebar_visible: nil, &on_progress)
              key = dynamic_cache_key(width, height, sidebar_visible: sidebar_visible)
              cached = key ? load_cached_pages(doc, key) : nil
              if cached&.any?
                annotate_profile(pagination_cache: 'hit')
                return Result.new(pages: cached, cached: true)
              end

              layout = layout_for(width, height, sidebar_visible: sidebar_visible)
              return Result.new(pages: [], cached: false) if layout[:lines_per_page] <= 0

              wrapper = resolve_wrapping_service
              formatter = resolve_formatting_service
              pages = DynamicPageMapBuilder.build(
                doc,
                layout[:col_width],
                layout[:lines_per_page],
                wrapper: wrapper,
                formatter: formatter,
                config: @config_reader,
                text_metrics: @text_metrics
              ) do |idx, total|
                on_progress&.call(idx, total)
              end

              if key
                save_cache(doc, key, pages)
                annotate_profile(pagination_cache: 'miss')
              end
              Result.new(pages: pages, cached: false)
            end

            def build_absolute(doc:, width:, height:, &on_progress)
              layout = layout_for(width, height)
              return [] if layout[:lines_per_page] <= 0

              wrapper = resolve_wrapping_service
              AbsolutePageMapBuilder.build(
                doc,
                layout[:col_width],
                layout[:lines_per_page],
                wrapper
              ) do |done, total|
                on_progress&.call(done, total)
              end
            end

            def compact_pages(pages)
              pages.map do |p|
                {
                  'chapter_index' => p[:chapter_index],
                  'page_in_chapter' => p[:page_in_chapter],
                  'total_pages_in_chapter' => p[:total_pages_in_chapter],
                  'start_line' => p[:start_line],
                  'end_line' => p[:end_line],
                }
              end
            end

            private

            def layout_for(width, height, sidebar_visible: nil)
              col_width, content_height = @metrics_calculator.layout(
                width,
                height,
                sidebar_visible: sidebar_visible
              )
              lines_per_page = @metrics_calculator.lines_per_page_for(content_height)
              { col_width: col_width, lines_per_page: lines_per_page }
            end

            def dynamic_cache_key(width, height, sidebar_visible: nil)
              view_mode = @config_reader.view_mode
              line_spacing = @config_reader.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
              return nil unless @pagination_cache

              kitty_images = @display_capabilities.kitty_images_enabled?(@config_reader)
              @pagination_cache.layout_key(
                width,
                height,
                view_mode,
                line_spacing,
                kitty_images: kitty_images,
                layout_variant: dynamic_layout_variant(sidebar_visible)
              )
            end

            def dynamic_layout_variant(sidebar_visible)
              sidebar_visible ? :sidebar : :base
            end

            def load_cached_pages(doc, key)
              return nil unless @pagination_cache

              cached = @pagination_cache.load_for_document(doc, key)
              cached if cached&.any?
            rescue StandardError
              nil
            end

            def save_cache(doc, key, pages)
              return unless @pagination_cache

              @pagination_cache.save_for_document(doc, key, compact_pages(pages))
            rescue StandardError
              nil
            end

            def annotate_profile(payload)
              @instrumentation.annotate(payload)
            rescue StandardError
              nil
            end

            def resolve_wrapping_service
              @wrapping_service
            end

            def resolve_formatting_service
              @formatting_service
            end
          end
        end
      end
    end
  end
end
