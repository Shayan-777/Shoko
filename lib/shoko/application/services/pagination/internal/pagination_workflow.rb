# frozen_string_literal: true

require 'shoko/application/ports/outbound/line_wrapper'
require 'shoko/application/ports/outbound/chapter_formatter'
require 'shoko/core/models/reader_settings'
require 'shoko/core/services/pagination/internal/absolute_page_map_builder'
require 'shoko/core/services/pagination/internal/dynamic_page_map_builder'

module Shoko
  module Application
    module Services
      module Pagination
        module Internal
          # Encapsulates pagination building, caching, and layout concerns so the
          # main PageCalculatorService remains focused on high-level orchestration.
          # Uses hexagonal ports for reading state - no direct state_store access.
          class PaginationWorkflow
            Result = Struct.new(:pages, :cached)

            # @param metrics_calculator [Object] Layout metrics calculator
            # @param pagination_cache [Object, nil] Pagination cache storage
            # @param display_capabilities [Application::Ports::Outbound::DisplayCapabilities]
            #   Display capability adapter (required)
            # @param instrumentation [Application::Ports::Outbound::Instrumentation] Instrumentation adapter (required)
            # @param text_metrics [Application::Ports::Outbound::TextMetrics] Text metrics adapter (required)
            # @param config_reader [Object] Config reader dependency (duck-typed, required)
            # @param line_wrapper [Application::Ports::Outbound::LineWrapper, nil] Optional wrapping adapter
            # @param chapter_formatter [Application::Ports::Outbound::ChapterFormatter, nil] Optional formatting adapter
            def initialize(metrics_calculator:, display_capabilities:, instrumentation:, text_metrics:,
                           config_reader:, layout_resolver: nil, pagination_cache: nil,
                           line_wrapper: nil, chapter_formatter: nil)
              @metrics_calculator = metrics_calculator
              @pagination_cache = pagination_cache
              @display_capabilities = display_capabilities
              @instrumentation = instrumentation
              @text_metrics = text_metrics
              @config_reader = config_reader
              @layout_resolver = layout_resolver
              @line_wrapper = line_wrapper
              @chapter_formatter = chapter_formatter
            end

            def build_dynamic(doc:, width:, height:, &on_progress)
              key = dynamic_cache_key(width, height)
              cached_result = cached_dynamic_result(doc, key)
              return cached_result if cached_result

              layout = layout_for(width, height)
              return Result.new(pages: [], cached: false) if layout[:lines_per_page] <= 0

              pages = build_dynamic_pages(doc, layout, &on_progress)
              cache_dynamic_pages(doc, key, pages)
              Result.new(pages: pages, cached: false)
            end

            def build_absolute(doc:, width:, height:, &on_progress)
              layout = layout_for(width, height)
              return [] if layout[:lines_per_page] <= 0

              wrapper = resolve_wrapping_service
              Shoko::Core::Services::Pagination::Internal::AbsolutePageMapBuilder.build(
                doc,
                layout[:col_width],
                layout[:lines_per_page],
                wrapper,
                text_metrics: @text_metrics
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

            def layout_for(width, height)
              col_width, content_height = @metrics_calculator.layout(width, height)
              lines_per_page = @metrics_calculator.lines_per_page_for(content_height)
              { col_width: col_width, lines_per_page: lines_per_page }
            end

            def cached_dynamic_result(doc, key)
              return nil unless key

              cached = load_cached_pages(doc, key)
              return nil unless cached&.any?

              annotate_profile(pagination_cache: 'hit')
              Result.new(pages: cached, cached: true)
            end

            def build_dynamic_pages(doc, layout, &)
              Shoko::Core::Services::Pagination::Internal::DynamicPageMapBuilder.build(
                doc,
                layout[:col_width],
                layout[:lines_per_page],
                line_wrapper: resolve_wrapping_service,
                chapter_formatter: resolve_formatting_service,
                config: @config_reader,
                text_metrics: @text_metrics,
                &
              )
            end

            def cache_dynamic_pages(doc, key, pages)
              return unless key

              save_cache(doc, key, pages)
              annotate_profile(pagination_cache: 'miss')
            end

            def dynamic_cache_key(width, height)
              return nil unless @pagination_cache

              resolved_layout(width, height).cache_key
            end

            def load_cached_pages(doc, key)
              return nil unless @pagination_cache

              cached = @pagination_cache.load_for_document(doc, key)
              cached if cached&.any?
            end

            def save_cache(doc, key, pages)
              return unless @pagination_cache

              @pagination_cache.save_for_document(doc, key, compact_pages(pages))
            end

            def annotate_profile(payload)
              @instrumentation.annotate(payload)
            end

            def resolve_wrapping_service
              @line_wrapper
            end

            def resolve_formatting_service
              @chapter_formatter
            end

            def resolved_layout(width, height)
              return fallback_layout(width, height) unless @layout_resolver

              @layout_resolver.resolve(
                config_reader: @config_reader,
                width: width,
                height: height
              )
            end

            def fallback_layout(width, height)
              view_mode = @config_reader.view_mode
              line_spacing = @config_reader.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
              kitty_images = @display_capabilities.kitty_images_enabled?(@config_reader)
              Struct.new(:cache_key).new(
                @pagination_cache.layout_key(
                  width,
                  height,
                  view_mode,
                  line_spacing,
                  kitty_images: kitty_images,
                  layout_variant: :base
                )
              )
            end
          end
        end
      end
    end
  end
end
