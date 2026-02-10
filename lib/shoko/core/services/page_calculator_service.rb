# frozen_string_literal: true

require_relative 'base_service'
require_relative 'pagination/internal/absolute_page_map_builder'
require_relative 'pagination/internal/dynamic_page_map_builder'
require_relative 'pagination/internal/page_hydrator'
require_relative 'pagination/internal/pagination_workflow'
require_relative 'pagination/internal/layout_metrics_calculator'
require_relative '../ports/config_reader'
require_relative '../ports/state_writer'
require_relative '../ports/text_metrics'
require_relative '../ports/display_capabilities'
require_relative '../ports/instrumentation'
require_relative '../ports/ui_state_reader'

module Shoko
  module Core
    module Services
      # Service for page calculations with full PageManager functionality.
      class PageCalculatorService
        attr_reader :pages_data

        DYNAMIC_LAYOUT_CACHE_LIMIT = 8

        def initialize(text_metrics:, display_capabilities:, instrumentation:, config_reader:, ui_state_reader:,
                       reader_state_reader: nil, layout_service: nil, pagination_cache: nil, wrapping_service: nil,
                       formatting_service: nil, logger: nil)
          @logger = logger || NullLogger.new
          @text_metrics = text_metrics
          @display_capabilities = display_capabilities
          @instrumentation = instrumentation
          @config_reader = config_reader
          @ui_state_reader = ui_state_reader
          @reader_state_reader = reader_state_reader
          @text_wrapper = DefaultTextWrapper.new(text_metrics: @text_metrics)
          @pages_data = []
          @chapter_page_index = {}
          @wrapping_service = wrapping_service
          @formatting_service = formatting_service
          @dynamic_layout_pages = {}
          @dynamic_layout_order = []
          @active_dynamic_layout_key = nil
          @metrics_calculator = Pagination::Internal::LayoutMetricsCalculator.new(
            config_reader: @config_reader,
            ui_state_reader: @ui_state_reader,
            layout_service: layout_service,
            reader_state_reader: @reader_state_reader
          )
          @pagination_cache = pagination_cache
          @pagination_workflow = Pagination::Internal::PaginationWorkflow.new(
            metrics_calculator: @metrics_calculator,
            pagination_cache: @pagination_cache,
            text_metrics: @text_metrics,
            display_capabilities: @display_capabilities,
            instrumentation: @instrumentation,
            config_reader: @config_reader,
            wrapping_service: wrapping_service,
            formatting_service: formatting_service
          )
          @page_hydrator = Pagination::Internal::PageHydrator.new(
            text_wrapper: @text_wrapper,
            metrics_calculator: @metrics_calculator,
            config_reader: @config_reader,
            ui_state_reader: @ui_state_reader,
            wrapping_service: wrapping_service,
            formatting_service: formatting_service
          )
        end

        # Build complete page map (PageManager compatibility)
        # @param config_reader [Core::Ports::ConfigReader] Port for reading config
        def build_page_map(terminal_width, terminal_height, doc, config_reader:, sidebar_visible: nil, &)
          return unless config_reader.page_numbering_mode == :dynamic

          visibility = resolve_sidebar_visibility(sidebar_visible)
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
        def get_page(page_index)
          return nil if @pages_data.empty?
          return @pages_data.first if page_index.negative?
          return @pages_data.last if page_index >= @pages_data.size

          page = @pages_data[page_index]
          return page if formatted_lines?(page[:lines])

          hydrated = measure_with_instrumentation('page_map.hydrate') do
            doc = resolve_document_reference
            @page_hydrator.hydrate(page, doc, prefer_formatting: true)
          rescue StandardError => e
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
        # @param config_reader [Core::Ports::ConfigReader] Port for reading config (unused, kept for API compatibility)
        # @yield [done, total] optional progress callback
        def build_absolute_page_map(terminal_width, terminal_height, doc, config_reader:)
          # Compute layout metrics based on current config (uses injected config_reader)
          col_width, content_height = @metrics_calculator.layout(terminal_width, terminal_height)
          lines_per_page = @metrics_calculator.lines_per_page_for(content_height)

          Pagination::Internal::AbsolutePageMapBuilder.build(doc, col_width, lines_per_page,
                                                             @wrapping_service) do |done, total|
            yield(done, total) if block_given?
          end
        end

        # --- Unified orchestration helpers ---
        # Build dynamic (lazy) page map and sync total to state. Accepts optional progress callback.
        # @param state_writer [Core::Ports::StateWriter] Port for writing state
        # @param config_reader [Core::Ports::ConfigReader] Port for reading config
        def build_dynamic_map!(width, height, doc, state_writer:, config_reader:, &)
          sidebar_visible = resolve_sidebar_visibility(nil)
          pages = build_dynamic_pages(width, height, doc, sidebar_visible: sidebar_visible, &)
          activate_dynamic_layout_pages(pages, width, height, sidebar_visible: sidebar_visible)
          precompute_sidebar_variant(width, height, doc, sidebar_visible)
          state_writer.update_pagination_state(
            total_pages: total_pages,
            last_width: width,
            last_height: height
          )
          @pages_data
        end

        # Switches dynamic pagination to a specific layout variant (base/sidebar)
        # and preserves reading position via line offset mapping.
        def switch_dynamic_layout_variant!(width, height, doc, sidebar_visible:, state_writer:, reader_state_reader:)
          return :pass unless @config_reader.page_numbering_mode == :dynamic
          return :missing unless doc

          current_page = raw_page_data(reader_state_reader.current_page_index.to_i)
          chapter_index = (current_page && current_page[:chapter_index]) || reader_state_reader.current_chapter
          line_offset = current_page ? current_page[:start_line].to_i : 0

          pages = dynamic_layout_pages_for(width, height, doc, sidebar_visible: sidebar_visible)
          activate_dynamic_layout_pages(pages, width, height, sidebar_visible: sidebar_visible)

          page_index = find_page_index(chapter_index.to_i, line_offset)
          state_writer.update_pagination_state(
            total_pages: total_pages,
            last_width: width,
            last_height: height
          )
          state_writer.update_page(current_page_index: page_index)
          precompute_sidebar_variant(width, height, doc, sidebar_visible)
          :switched
        rescue StandardError => e
          logger.debug('switch_dynamic_layout_variant failed', error: e.message)
          :error
        end

        # Build absolute page map and sync map/total/last dims to state. Accepts optional progress callback.
        # @param state_writer [Core::Ports::StateWriter] Port for writing state
        # @param config_reader [Core::Ports::ConfigReader] Port for reading config
        def build_absolute_map!(width, height, doc, state_writer:, config_reader:, &)
          map = build_absolute_page_map(width, height, doc, config_reader: config_reader, &)
          state_writer.update_pagination_state(
            page_map: map,
            total_pages: map.sum,
            last_width: width,
            last_height: height
          )
          map
        end

        # Apply precise pending progress (dynamic mode) if present in state
        # @param reader_state_reader [Core::Ports::ReaderStateReader] Port for reading reader state
        # @param state_writer [Core::Ports::StateWriter] Port for writing state
        def apply_pending_precise_restore!(reader_state_reader, state_writer:)
          pending = reader_state_reader.pending_progress
          return unless pending && pending[:line_offset]

          ch = pending[:chapter_index] || reader_state_reader.current_chapter
          idx = find_page_index(ch, pending[:line_offset].to_i)
          state_writer.update_page(current_page_index: idx) if idx && idx >= 0
          state_writer.update_selections(pending_progress: nil)
        rescue StandardError => e
          logger.debug('apply_pending_precise_restore failed', error: e.message)
        end

        def resolve_document_reference
          # Document is intentionally late-bound: it changes during the app
          # lifecycle and isn't available when this singleton is first created.
          @doc_ref
        end

        def formatted_lines?(lines)
          first = Array(lines).find { |ln| !ln.nil? }
          first.respond_to?(:segments) && first.respond_to?(:text)
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

        # Hydrate from cached pagination without recomputation
        # @param state_writer [Core::Ports::StateWriter, nil] Optional port for writing state
        def hydrate_from_cache(pages, state_writer: nil, width: nil, height: nil)
          return nil unless pages.is_a?(Array)

          @pages_data = pages
          cache_dynamic_layout_pages(
            dynamic_layout_key(width, height, sidebar_visible: resolve_sidebar_visibility(nil)),
            pages
          )
          rebuild_page_index!
          total = @pages_data.size
          state_writer&.update_pagination_state(
            total_pages: total,
            last_width: width,
            last_height: height
          )
          total
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
          rebuild_page_index!
        end

        def precompute_sidebar_variant(width, height, doc, active_sidebar_visible)
          return unless @config_reader.view_mode == :single

          alternate = !active_sidebar_visible
          key = dynamic_layout_key(width, height, sidebar_visible: alternate)
          return if @dynamic_layout_pages.key?(key)

          pages = build_dynamic_pages(width, height, doc, sidebar_visible: alternate)
          cache_dynamic_layout_pages(key, pages)
        rescue StandardError => e
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
        rescue StandardError
          [width.to_i, height.to_i, sidebar_visible ? :sidebar : :base].join(':')
        end

        def resolve_sidebar_visibility(override)
          return override unless override.nil?

          @reader_state_reader&.sidebar_visible? == true
        rescue StandardError
          false
        end

        def measure_with_instrumentation(metric, &)
          @instrumentation.measure(metric, &)
        end
      end

      # Default text wrapping implementation
      class DefaultTextWrapper
        # @param text_metrics [Core::Ports::TextMetrics] Required text metrics implementation
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
