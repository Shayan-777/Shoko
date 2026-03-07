# frozen_string_literal: true

require_relative 'base_service'
require_relative 'pagination/internal/absolute_page_map_builder'
require_relative 'pagination/internal/dynamic_page_map_builder'
require_relative 'pagination/internal/page_hydrator'
require_relative 'pagination/internal/pagination_workflow'
require_relative 'pagination/internal/layout_metrics_calculator'
require_relative '../models/content_block'
require_relative '../ports/outbound/text_metrics'
require_relative '../ports/outbound/display_capabilities'
require_relative '../ports/outbound/instrumentation'
require_relative '../ports/outbound/line_wrapper'
require_relative '../ports/outbound/chapter_formatter'

module Shoko
  module Core
    module Services
      # Service for page calculations with full PageManager functionality.
      class PageCalculatorService
        attr_reader :pages_data

        DYNAMIC_LAYOUT_CACHE_LIMIT = 8

        def initialize(text_metrics:, display_capabilities:, instrumentation:, config_reader:,
                       layout_service: nil, pagination_cache: nil, wrapping_service: nil,
                       formatting_service: nil, logger: nil)
          validate_optional_pagination_ports!(wrapping_service: wrapping_service,
                                              formatting_service: formatting_service)

          @logger = logger || NullLogger.new
          @text_metrics = text_metrics
          @display_capabilities = display_capabilities
          @instrumentation = instrumentation
          @config_reader = config_reader
          @text_wrapper = DefaultTextWrapper.new(text_metrics: @text_metrics)
          @pages_data = []
          @chapter_page_index = {}
          @wrapping_service = wrapping_service
          @formatting_service = formatting_service
          @dynamic_layout_pages = {}
          @dynamic_layout_order = []
          @active_dynamic_layout_key = nil
          @last_layout_width = nil
          @last_layout_height = nil
          @last_sidebar_visible = false
          @metrics_calculator = Pagination::Internal::LayoutMetricsCalculator.new(
            config_reader: @config_reader,
            layout_service: layout_service
          )
          @pagination_cache = pagination_cache
          @pagination_workflow = Pagination::Internal::PaginationWorkflow.new(
            metrics_calculator: @metrics_calculator,
            pagination_cache: @pagination_cache,
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
        end

        # Resets all session-specific state so the singleton is safe for reuse
        # across reader sessions. Must be called before a new book is opened.
        def reset_session!
          @pages_data = []
          @chapter_page_index = {}
          @dynamic_layout_pages = {}
          @dynamic_layout_order = []
          @active_dynamic_layout_key = nil
          @last_layout_width = nil
          @last_layout_height = nil
          @last_sidebar_visible = false
          @doc_ref = nil
        end

        # Build complete page map (PageManager compatibility)
        # @param config_reader [Object] Config reader dependency (duck-typed)
        def build_page_map(terminal_width, terminal_height, doc, config_reader:, sidebar_visible: false, &)
          return unless config_reader.page_numbering_mode == :dynamic

          visibility = normalize_sidebar_visibility(sidebar_visible)
          pages = build_dynamic_pages(
            terminal_width,
            terminal_height,
            doc,
            sidebar_visible: visibility,
            &
          )
          activate_dynamic_layout_pages(pages, terminal_width, terminal_height, sidebar_visible: visibility)
          @pages_data
        end

        # Get page data by index (PageManager compatibility)
        def get_page(page_index, width: nil, height: nil, sidebar_visible: nil)
          return nil if @pages_data.empty?
          return @pages_data.first if page_index.negative?
          return @pages_data.last if page_index >= @pages_data.size

          page = @pages_data[page_index]
          return page if formatted_lines?(page[:lines])

          layout = resolve_layout_context(width: width, height: height, sidebar_visible: sidebar_visible)
          hydrated = measure_with_instrumentation('page_map.hydrate') do
            doc = resolve_document_reference
            @page_hydrator.hydrate(
              page,
              doc,
              width: layout[:width],
              height: layout[:height],
              sidebar_visible: layout[:sidebar_visible],
              prefer_formatting: true
            )
          rescue Shoko::Error => e
            logger.debug('page_hydrator.hydrate failed', page_index: page_index, error: e.message)
            page
          end

          @pages_data[page_index] = hydrated if hydrated
          hydrated
        end

        # Find page index for chapter and line offset (PageManager compatibility)
        def find_page_index(chapter_index, line_offset)
          pages = @chapter_page_index[chapter_index]
          return 0 unless pages && !pages.empty?

          match = pages.bsearch { |page| line_offset <= page[:end_line].to_i }
          return match[:global_index] if match && match[:global_index]

          pages.last[:global_index] || 0
        end

        # Total pages built in map (PageManager compatibility)
        def total_pages
          @pages_data.size
        end

        # Build absolute mode page map (per-chapter pages) with progress callback.
        # Returns an array of pages per chapter.
        # @param terminal_width [Integer] Terminal width
        # @param terminal_height [Integer] Terminal height
        # @param doc [Object] Document object
        # @param config_reader [Object] Config reader dependency (duck-typed, unused here)
        # @yield [done, total] optional progress callback
        def build_absolute_page_map(terminal_width, terminal_height, doc, config_reader:)
          # Compute layout metrics based on current config (uses injected config_reader)
          col_width, content_height = @metrics_calculator.layout(terminal_width, terminal_height)
          lines_per_page = @metrics_calculator.lines_per_page_for(content_height)

          Pagination::Internal::AbsolutePageMapBuilder.build(doc, col_width, lines_per_page,
                                                             @wrapping_service, text_metrics: @text_metrics) do |done, total|
            yield(done, total) if block_given?
          end
        end

        # --- Unified orchestration helpers ---
        # Build dynamic (lazy) page map and return sync payload for application orchestration.
        # @param config_reader [Object] Config reader dependency (duck-typed)
        def build_dynamic_map!(width, height, doc, config_reader:, sidebar_visible:, &)
          visibility = normalize_sidebar_visibility(sidebar_visible)
          pages = build_dynamic_pages(width, height, doc, sidebar_visible: visibility, &)
          activate_dynamic_layout_pages(pages, width, height, sidebar_visible: visibility)
          precompute_sidebar_variant(width, height, doc, visibility)
          {
            pages: @pages_data,
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
          current_page = raw_page_data(reader_state_reader.current_page_index.to_i)
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
          set_layout_context(width: width, height: height, sidebar_visible: false)
          {
            page_map: map,
            total_pages: map.sum,
            last_width: width,
            last_height: height,
          }
        end

        # Build the precise pending-restore payload (dynamic mode), if present.
        def apply_pending_precise_restore!(reader_state_reader)
          pending = reader_state_reader.pending_progress
          return unless pending && pending[:line_offset]

          ch = pending[:chapter_index] || reader_state_reader.current_chapter
          idx = find_page_index(ch, pending[:line_offset].to_i)
          payload = { clear_pending_progress: true }
          payload[:current_page_index] = idx if idx && idx >= 0
          payload
        rescue Shoko::Error => e
          logger.debug('apply_pending_precise_restore failed', error: e.message)
          nil
        end

        def resolve_document_reference
          # Document is intentionally late-bound: it changes during the app
          # lifecycle and isn't available when this singleton is first created.
          @doc_ref
        end

        def formatted_lines?(lines)
          first = Array(lines).find { |ln| !ln.nil? }
          first.is_a?(Shoko::Core::Models::DisplayLine)
        end

        def raw_page_data(page_index)
          return nil if @pages_data.empty?

          idx = page_index.to_i
          idx = 0 if idx.negative?
          idx = @pages_data.length - 1 if idx >= @pages_data.length
          @pages_data[idx]
        end

        def rebuild_page_index!
          @chapter_page_index = Hash.new { |h, k| h[k] = [] }
          @pages_data.each_with_index do |page, idx|
            ch = page[:chapter_index] || 0
            entry = page.merge(global_index: idx)
            @chapter_page_index[ch] << entry
          end
          @chapter_page_index.each_value { |arr| arr.sort_by! { |p| p[:end_line].to_i } }
        end

        # Hydrate from cached pagination without recomputation and return sync payload.
        def hydrate_from_cache(pages, width: nil, height: nil, sidebar_visible: false, doc: nil)
          return nil unless pages.is_a?(Array)

          visibility = normalize_sidebar_visibility(sidebar_visible)
          @doc_ref = doc if doc
          @pages_data = pages
          if width && height
            cache_dynamic_layout_pages(
              dynamic_layout_key(width, height, sidebar_visible: visibility),
              pages
            )
            set_layout_context(width: width, height: height, sidebar_visible: visibility)
          end
          rebuild_page_index!
          total = @pages_data.size
          {
            total_pages: total,
            last_width: width,
            last_height: height,
          }
        end

        private

        attr_reader :logger

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
          pages = @dynamic_layout_pages[key]
          return pages if pages

          pages = build_dynamic_pages(width, height, doc, sidebar_visible: sidebar_visible)
          cache_dynamic_layout_pages(key, pages)
          pages
        end

        def activate_dynamic_layout_pages(pages, width, height, sidebar_visible:)
          key = dynamic_layout_key(width, height, sidebar_visible: sidebar_visible)
          cache_dynamic_layout_pages(key, pages)
          @active_dynamic_layout_key = key
          @pages_data = pages
          set_layout_context(width: width, height: height, sidebar_visible: sidebar_visible)
          rebuild_page_index!
        end

        def precompute_sidebar_variant(width, height, doc, active_sidebar_visible)
          return unless @config_reader.view_mode == :single

          alternate = !active_sidebar_visible
          key = dynamic_layout_key(width, height, sidebar_visible: alternate)
          return if @dynamic_layout_pages.key?(key)

          pages = build_dynamic_pages(width, height, doc, sidebar_visible: alternate)
          cache_dynamic_layout_pages(key, pages)
        rescue Shoko::Error => e
          logger.debug('precompute_sidebar_variant failed', error: e.message)
        end

        def cache_dynamic_layout_pages(key, pages)
          return unless key && pages.is_a?(Array)

          @dynamic_layout_pages[key] = pages
          @dynamic_layout_order.delete(key)
          @dynamic_layout_order << key
          while @dynamic_layout_order.length > DYNAMIC_LAYOUT_CACHE_LIMIT
            oldest = @dynamic_layout_order.shift
            next if oldest == @active_dynamic_layout_key

            @dynamic_layout_pages.delete(oldest)
          end
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

        def set_layout_context(width:, height:, sidebar_visible:)
          @last_layout_width = width.to_i
          @last_layout_height = height.to_i
          @last_sidebar_visible = sidebar_visible == true
        end

        def validate_optional_pagination_ports!(wrapping_service:, formatting_service:)
          if wrapping_service && !wrapping_service.is_a?(Shoko::Core::Ports::Outbound::LineWrapper)
            raise ArgumentError, 'wrapping_service must implement Core::Ports::Outbound::LineWrapper'
          end
          return unless formatting_service && !formatting_service.is_a?(Shoko::Core::Ports::Outbound::ChapterFormatter)

          raise ArgumentError, 'formatting_service must implement Core::Ports::Outbound::ChapterFormatter'
        end

        def resolve_layout_context(width:, height:, sidebar_visible:)
          context = context_from_explicit_layout(width: width, height: height, sidebar_visible: sidebar_visible)
          return context if context

          context_from_last_layout || context_from_active_dynamic_key || default_layout_context
        end

        def context_from_explicit_layout(width:, height:, sidebar_visible:)
          return nil unless width && height

          {
            width: width.to_i,
            height: height.to_i,
            sidebar_visible: sidebar_visible.nil? ? @last_sidebar_visible : normalize_sidebar_visibility(sidebar_visible),
          }
        end

        def context_from_last_layout
          return nil unless @last_layout_width.to_i.positive? && @last_layout_height.to_i.positive?

          {
            width: @last_layout_width,
            height: @last_layout_height,
            sidebar_visible: @last_sidebar_visible,
          }
        end

        def context_from_active_dynamic_key
          key = @active_dynamic_layout_key.to_s
          return nil if key.empty?

          parts = key.split(':')
          width = parts[0].to_i
          height = parts[1].to_i
          variant = parts[-1].to_s
          return nil unless width.positive? && height.positive?

          {
            width: width,
            height: height,
            sidebar_visible: variant == 'sidebar',
          }
        end

        def default_layout_context
          { width: 80, height: 24, sidebar_visible: false }
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
# NOTE: Former helper that prepopulated lines for cached pages has been
# removed to avoid blocking first paint. Lines are populated lazily in
# #get_page when needed.
