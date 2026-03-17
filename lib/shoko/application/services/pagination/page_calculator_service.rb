# frozen_string_literal: true

require_relative 'internal/dynamic_layout_cache'
require_relative 'internal/layout_metrics_calculator'
require_relative 'internal/page_hydration_facade'
require_relative 'internal/page_hydrator'
require_relative 'internal/pagination_workflow'
require_relative 'internal/restore_mapping_service'
require_relative '../../../core/models/reader_settings'
require_relative '../../../core/services/pagination/internal/absolute_page_map_builder'
require_relative '../../../core/services/null_logger'
require_relative '../../../core/ports/outbound/text_metrics'
require_relative '../../../core/ports/outbound/display_capabilities'
require_relative '../../../core/ports/outbound/instrumentation'
require_relative '../../../core/ports/outbound/line_wrapper'
require_relative '../../../core/ports/outbound/chapter_formatter'
require_relative '../../../core/ports/outbound/dynamic_page_source'

module Shoko
  module Application
    module Services
      module Pagination
        # Application pagination service that owns layout variants, cache orchestration, and hydration.
        class PageCalculatorService
          include Core::Ports::Outbound::DynamicPageSource

          DYNAMIC_LAYOUT_CACHE_LIMIT = 8

          def initialize(text_metrics:, display_capabilities:, instrumentation:, config_reader:,
                         layout_service: nil, pagination_cache: nil, wrapping_service: nil,
                         formatting_service: nil, logger: nil)
            validate_optional_pagination_ports!(wrapping_service: wrapping_service,
                                                formatting_service: formatting_service)

            @logger = logger || Shoko::Core::Services::NullLogger.new
            @text_metrics = text_metrics
            @display_capabilities = display_capabilities
            @instrumentation = instrumentation
            @config_reader = config_reader
            @wrapping_service = wrapping_service
            @text_wrapper = DefaultTextWrapper.new(text_metrics: @text_metrics)
            @metrics_calculator = Pagination::Internal::LayoutMetricsCalculator.new(
              config_reader: @config_reader,
              layout_service: layout_service
            )
            @pagination_workflow = Pagination::Internal::PaginationWorkflow.new(
              metrics_calculator: @metrics_calculator,
              pagination_cache: pagination_cache,
              text_metrics: @text_metrics,
              display_capabilities: @display_capabilities,
              instrumentation: @instrumentation,
              config_reader: @config_reader,
              line_wrapper: wrapping_service,
              chapter_formatter: formatting_service
            )
            @page_hydrator = Pagination::Internal::PageHydrator.new(
              text_wrapper: @text_wrapper,
              metrics_calculator: @metrics_calculator,
              config_reader: @config_reader,
              line_wrapper: wrapping_service,
              chapter_formatter: formatting_service
            )
            @dynamic_layout_cache = Pagination::Internal::DynamicLayoutCache.new(
              cache_limit: DYNAMIC_LAYOUT_CACHE_LIMIT
            )
            @restore_mapping = Pagination::Internal::RestoreMappingService.new
            @page_hydration = Pagination::Internal::PageHydrationFacade.new(
              page_hydrator: @page_hydrator,
              pages_reader: -> { @dynamic_layout_cache.pages_data },
              page_writer: ->(page_index, page) { @dynamic_layout_cache.replace_page(page_index, page) },
              document_reader: -> { resolve_document_reference },
              layout_context_reader: lambda do |width:, height:, sidebar_visible:|
                @dynamic_layout_cache.layout_context(
                  width: width,
                  height: height,
                  sidebar_visible: sidebar_visible
                )
              end,
              logger: @logger
            )
          end

          def pages_data
            @dynamic_layout_cache.pages_data
          end

          # Resets all session-specific state so the singleton is safe for reuse
          # across reader sessions. Must be called before a new book is opened.
          def reset_session!
            @dynamic_layout_cache.reset!
            @restore_mapping.reset!
            @doc_ref = nil
          end

          # Get page data by index, hydrating the page if formatted lines are needed.
          def get_page(page_index, width: nil, height: nil, sidebar_visible: nil)
            measure_with_instrumentation('page_map.hydrate') do
              @page_hydration.fetch(page_index, width: width, height: height, sidebar_visible: sidebar_visible)
            end
          end

          # Find the page index for the given chapter and line offset.
          def find_page_index(chapter_index, line_offset)
            @restore_mapping.find_page_index(chapter_index, line_offset)
          end

          # Total pages currently loaded in the active page map.
          def total_pages
            @dynamic_layout_cache.total_pages
          end

          # Build dynamic (lazy) page map and return sync payload for application orchestration.
          # @param config_reader [Object] Config reader dependency (duck-typed)
          def build_dynamic_map!(width, height, doc, config_reader:, sidebar_visible:, &)
            visibility = normalize_sidebar_visibility(sidebar_visible)
            pages = build_dynamic_pages(width, height, doc, sidebar_visible: visibility, &)
            activate_dynamic_layout_pages(pages, width, height, sidebar_visible: visibility)
            precompute_sidebar_variant(width, height, doc, visibility)
            {
              pages: pages_data,
              total_pages: total_pages,
              last_width: width,
              last_height: height,
            }
          end

          # Switches dynamic pagination to a specific layout variant (base/sidebar)
          # and preserves reading position via line offset mapping.
          def switch_dynamic_layout_variant!(width, height, doc, sidebar_visible:, reader_state_reader:)
            return { status: :pass } unless @config_reader.page_numbering_mode == :dynamic
            return { status: :missing } unless doc

            visibility = normalize_sidebar_visibility(sidebar_visible)
            current_page = @dynamic_layout_cache.raw_page(reader_state_reader.current_page_index.to_i)
            chapter_index = (current_page && current_page[:chapter_index]) || reader_state_reader.current_chapter
            line_offset = current_page ? current_page[:start_line].to_i : 0

            pages = dynamic_layout_pages_for(width, height, doc, sidebar_visible: visibility)
            activate_dynamic_layout_pages(pages, width, height, sidebar_visible: visibility)

            page_index = find_page_index(chapter_index.to_i, line_offset)
            precompute_sidebar_variant(width, height, doc, visibility)
            {
              status: :switched,
              current_page_index: page_index,
              total_pages: total_pages,
              last_width: width,
              last_height: height,
            }
          rescue Shoko::Error => e
            logger.debug('switch_dynamic_layout_variant failed', error: e.message)
            { status: :error }
          end

          # Build absolute page map and return sync payload for application orchestration.
          # @param config_reader [Object] Config reader dependency (duck-typed)
          def build_absolute_map!(width, height, doc, config_reader:, &)
            map = build_absolute_page_map(width, height, doc, config_reader: config_reader, &)
            @dynamic_layout_cache.remember_layout(width: width, height: height, sidebar_visible: false)
            {
              page_map: map,
              total_pages: map.sum,
              last_width: width,
              last_height: height,
            }
          end

          # Build the precise pending-restore payload (dynamic mode), if present.
          def apply_pending_precise_restore!(reader_state_reader)
            @restore_mapping.apply_pending_precise_restore!(reader_state_reader)
          rescue Shoko::Error => e
            logger.debug('apply_pending_precise_restore failed', error: e.message)
            nil
          end

          def resolve_document_reference
            # Document is intentionally late-bound: it changes during the app
            # lifecycle and isn't available when this singleton is first created.
            @doc_ref
          end

          # Hydrate from cached pagination without recomputation and return sync payload.
          def hydrate_from_cache(pages, width: nil, height: nil, sidebar_visible: false, doc: nil)
            return nil unless pages.is_a?(Array)

            visibility = normalize_sidebar_visibility(sidebar_visible)
            @doc_ref = doc if doc
            key = width && height ? dynamic_layout_key(width, height, sidebar_visible: visibility) : nil
            @dynamic_layout_cache.load_pages(
              pages: pages,
              key: key,
              width: width,
              height: height,
              sidebar_visible: visibility
            )
            @restore_mapping.rebuild!(pages_data)
            {
              total_pages: total_pages,
              last_width: width,
              last_height: height,
            }
          end

          private

          attr_reader :logger

          def build_absolute_page_map(terminal_width, terminal_height, doc, config_reader:)
            col_width, content_height = @metrics_calculator.layout(terminal_width, terminal_height)
            lines_per_page = @metrics_calculator.lines_per_page_for(content_height)

            Shoko::Core::Services::Pagination::Internal::AbsolutePageMapBuilder.build(
              doc,
              col_width,
              lines_per_page,
              @wrapping_service,
              text_metrics: @text_metrics
            ) do |done, total|
              yield(done, total) if block_given?
            end
          end

          def build_dynamic_pages(width, height, doc, sidebar_visible:, &on_progress)
            result = @pagination_workflow.build_dynamic(
              doc: doc,
              width: width,
              height: height,
              sidebar_visible: sidebar_visible,
              &on_progress
            )
            @doc_ref = doc
            result.pages
          end

          def dynamic_layout_pages_for(width, height, doc, sidebar_visible:)
            key = dynamic_layout_key(width, height, sidebar_visible: sidebar_visible)
            pages = @dynamic_layout_cache.cached_pages(key)
            return pages if pages

            pages = build_dynamic_pages(width, height, doc, sidebar_visible: sidebar_visible)
            @dynamic_layout_cache.cache_pages(key: key, pages: pages)
            pages
          end

          def activate_dynamic_layout_pages(pages, width, height, sidebar_visible:)
            key = dynamic_layout_key(width, height, sidebar_visible: sidebar_visible)
            @dynamic_layout_cache.activate(
              key: key,
              pages: pages,
              width: width,
              height: height,
              sidebar_visible: sidebar_visible
            )
            @restore_mapping.rebuild!(pages_data)
          end

          def precompute_sidebar_variant(width, height, doc, active_sidebar_visible)
            return unless @config_reader.view_mode == :single

            alternate = !active_sidebar_visible
            key = dynamic_layout_key(width, height, sidebar_visible: alternate)
            return if @dynamic_layout_cache.cached?(key)

            pages = build_dynamic_pages(width, height, doc, sidebar_visible: alternate)
            @dynamic_layout_cache.cache_pages(key: key, pages: pages)
          rescue Shoko::Error => e
            logger.debug('precompute_sidebar_variant failed', error: e.message)
          end

          def dynamic_layout_key(width, height, sidebar_visible:)
            view_mode = @config_reader.view_mode || :single
            line_spacing = @config_reader.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
            kitty_images = @display_capabilities.kitty_images_enabled?(@config_reader)
            variant = sidebar_visible ? :sidebar : :base
            [width.to_i, height.to_i, view_mode.to_sym, line_spacing.to_sym, kitty_images ? 'img1' : 'img0',
             variant].join(':')
          rescue Shoko::Error
            [width.to_i, height.to_i, sidebar_visible ? :sidebar : :base].join(':')
          end

          def normalize_sidebar_visibility(value)
            value == true
          end

          def validate_optional_pagination_ports!(wrapping_service:, formatting_service:)
            if wrapping_service && !wrapping_service.is_a?(Shoko::Core::Ports::Outbound::LineWrapper)
              raise ArgumentError, 'wrapping_service must implement Core::Ports::Outbound::LineWrapper'
            end
            return unless formatting_service && !formatting_service.is_a?(Shoko::Core::Ports::Outbound::ChapterFormatter)

            raise ArgumentError, 'formatting_service must implement Core::Ports::Outbound::ChapterFormatter'
          end

          def measure_with_instrumentation(metric, &)
            @instrumentation.measure(metric, &)
          end
        end

        # Default text wrapping implementation
        class DefaultTextWrapper
          # @param text_metrics [Core::Ports::Outbound::TextMetrics] Required text metrics implementation
          def initialize(text_metrics:)
            raise ArgumentError, 'text_metrics is required' unless text_metrics

            @text_metrics = text_metrics
          end

          def wrap_chapter_lines(lines, column_width)
            return [] if lines.empty? || column_width <= 0

            wrapped = []
            lines.each do |line|
              next if line.nil?

              if line.strip.empty?
                wrapped << ''
              else
                segments = @text_metrics.wrap_plain_text(line, column_width)
                wrapped.concat(segments)
              end
            end
            wrapped
          end
        end
      end
    end
  end
end
# NOTE: Former helper that prepopulated lines for cached pages has been
# removed to avoid blocking first paint. Lines are populated lazily in
# #get_page when needed.
