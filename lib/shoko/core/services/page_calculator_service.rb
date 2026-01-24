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
      # Enhanced service for page calculations with full PageManager functionality.
      # Migrated from legacy Services::PageManager with dependency injection.
      #
      # This service follows hexagonal architecture principles:
      # - Config reading goes through ConfigReader port
      # - Reader state reading goes through ReaderStateReader port
      # - UI state reading goes through UIStateReader port
      # - State writing goes through StateWriter port
      # - All dependencies injected via container (no fallback instantiation)
      class PageCalculatorService < BaseService
        attr_reader :pages_data

        def initialize(dependencies)
          super
          @text_metrics = resolve(:text_metrics)
          @display_capabilities = resolve(:display_capabilities)
          @instrumentation = resolve(:instrumentation)
          @config_reader = resolve(:config_reader)
          @ui_state_reader = resolve(:ui_state_reader)
          @text_wrapper = DefaultTextWrapper.new(text_metrics: @text_metrics)
          @pages_data = []
          @chapter_page_index = {}
          @layout_service = resolve_optional(:layout_service)
          @metrics_calculator = Pagination::Internal::LayoutMetricsCalculator.new(
            config_reader: @config_reader,
            ui_state_reader: @ui_state_reader,
            layout_service: @layout_service
          )
          @pagination_cache = resolve_optional(:pagination_cache)
          @pagination_workflow = Pagination::Internal::PaginationWorkflow.new(
            metrics_calculator: @metrics_calculator,
            dependencies: @dependencies,
            pagination_cache: @pagination_cache,
            text_metrics: @text_metrics,
            display_capabilities: @display_capabilities,
            instrumentation: @instrumentation,
            config_reader: @config_reader
          )
          @page_hydrator = Pagination::Internal::PageHydrator.new(
            dependencies: @dependencies,
            text_wrapper: @text_wrapper,
            metrics_calculator: @metrics_calculator,
            config_reader: @config_reader,
            ui_state_reader: @ui_state_reader
          )
        end

        # Build complete page map (PageManager compatibility)
        # @param config_reader [Core::Ports::ConfigReader] Port for reading config
        def build_page_map(terminal_width, terminal_height, doc, config_reader:, &)
          return unless config_reader.page_numbering_mode == :dynamic

          result = @pagination_workflow.build_dynamic(doc: doc,
                                                      width: terminal_width,
                                                      height: terminal_height,
                                                      &)
          @doc_ref = doc
          @pages_data = result.pages
          rebuild_page_index!
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
          rescue StandardError
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
          wrapper = begin
            @dependencies&.resolve(:wrapping_service)
          rescue StandardError
            nil
          end

          Pagination::Internal::AbsolutePageMapBuilder.build(doc, col_width, lines_per_page, wrapper) do |done, total|
            yield(done, total) if block_given?
          end
        end

        # --- Unified orchestration helpers ---
        # Build dynamic (lazy) page map and sync total to state. Accepts optional progress callback.
        # @param state_writer [Core::Ports::StateWriter] Port for writing state
        # @param config_reader [Core::Ports::ConfigReader] Port for reading config
        def build_dynamic_map!(width, height, doc, state_writer:, config_reader:, &)
          build_page_map(width, height, doc, config_reader: config_reader, &)
          rebuild_page_index!
          state_writer.update_pagination_state(total_pages: total_pages)
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
        rescue StandardError
          # no-op on failure
        end

        def resolve_document_reference
          return @doc_ref if @doc_ref

          @dependencies&.resolve(:document)
        rescue StandardError
          nil
        end

        def formatted_lines?(lines)
          first = Array(lines).find { |ln| !ln.nil? }
          first.respond_to?(:segments) && first.respond_to?(:text)
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
          rebuild_page_index!
          total = @pages_data.size
          state_writer&.update_pagination_state(
            total_pages: total,
            last_width: width,
            last_height: height
          )
          total
        end

        protected

        def required_dependencies
          %i[text_metrics display_capabilities instrumentation config_reader ui_state_reader]
        end

        private

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
