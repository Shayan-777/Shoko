# frozen_string_literal: true

require_relative '../pagination'
require_relative '../../ports/config_reader'
require_relative '../../ports/state_writer'

module Shoko
  module Core
    module Services
      module Pagination
        # Computes reader page information (current/total pages) for single and split view modes.
        # Encapsulates sizing logic so ReaderController can delegate without duplicating calculations.
        #
        # This class follows hexagonal architecture principles:
        # - Config reading goes through ConfigReader port
        # - Reader state reading goes through ReaderStateReader port
        # - State writing goes through StateWriter port
        # Uses hexagonal ports for reading state - no direct state_store access.
        class PageInfoCalculator
          def initialize(doc:, page_calculator:, layout_service:, terminal_service:,
                         pagination_orchestrator:, defer_page_map:,
                         config_reader:, reader_state_reader:, state_writer:)
            @doc = doc
            @page_calculator = page_calculator
            @layout_service = layout_service
            @terminal_service = terminal_service
            @pagination_orchestrator = pagination_orchestrator
            @defer_page_map = defer_page_map
            @config_reader = config_reader
            @reader_state_reader = reader_state_reader
            @state_writer = state_writer
          end

          def calculate
            return default_single unless show_page_numbers?

            view_mode = current_view_mode
            if view_mode == :split
              calculate_split_info
            else
              calculate_single_info
            end
          end

          private

          attr_reader :doc, :page_calculator, :layout_service, :terminal_service,
                      :pagination_orchestrator, :defer_page_map, :config_reader,
                      :reader_state_reader, :state_writer

          def calculate_single_info
            if dynamic_mode?
              calculate_dynamic_single
            else
              calculate_absolute_single
            end
          end

          def calculate_split_info
            if dynamic_mode?
              calculate_dynamic_split
            else
              calculate_absolute_split
            end
          end

          def calculate_dynamic_single
            return default_single unless page_calculator

            current_page = current_page_index + 1
            total_pages = total_pages_from_calculator

            {
              type: :single,
              current: current_page,
              total: total_pages,
            }
          end

          def calculate_dynamic_split
            return default_split unless page_calculator

            left_page = current_page_index + 1
            total_pages = total_pages_from_calculator
            right_page = [left_page + 1, total_pages].min

            {
              type: :split,
              left: { current: left_page, total: total_pages },
              right: { current: right_page, total: total_pages },
            }
          end

          def calculate_absolute_single
            layout = absolute_layout(current_view_mode)
            lines_per_page = layout[:lines_per_page]
            return default_single if lines_per_page <= 0

            ensure_absolute_page_map(layout[:width], layout[:height])

            page_map = page_map_from_state
            pages_before = pages_before_current_chapter(page_map)
            line_offset = line_offset_for_view(current_view_mode)
            page_in_chapter = page_in_chapter_for_offset(line_offset, lines_per_page)
            current_global_page = pages_before + page_in_chapter
            total_pages = total_pages_from_state

            {
              type: :single,
              current: current_global_page,
              total: total_pages.positive? ? total_pages : 0,
            }
          end

          def calculate_absolute_split
            layout = absolute_layout(:split)
            lines_per_page = layout[:lines_per_page]
            return default_split if lines_per_page <= 0

            ensure_absolute_page_map(layout[:width], layout[:height])

            page_map = page_map_from_state
            total_pages = total_pages_from_state
            return default_split unless total_pages.positive?

            pages_before = pages_before_current_chapter(page_map)

            left_line_offset = reader_state_reader.left_page
            left_page_in_chapter = page_in_chapter_for_offset(left_line_offset, lines_per_page)
            left_current = pages_before + left_page_in_chapter

            right_line_offset = reader_state_reader.right_page
            right_line_offset = lines_per_page if right_line_offset.to_i.zero?
            right_page_in_chapter = page_in_chapter_for_offset(right_line_offset, lines_per_page)
            right_current = [pages_before + right_page_in_chapter, total_pages].min

            {
              type: :split,
              left: { current: left_current, total: total_pages },
              right: { current: right_current, total: total_pages },
            }
          end

          def ensure_absolute_page_map(width, height)
            return if defer_page_map
            return unless page_calculator
            return unless config_reader && state_writer

            return unless page_map_empty? || size_changed?(width, height)

            pagination_orchestrator
              .session(doc: doc, page_calculator: page_calculator,
                       dimensions: [width, height], config_reader: config_reader,
                       reader_state_reader: reader_state_reader, state_writer: state_writer)
              &.build_full_map
          end

          def default_single
            { type: :single, current: 0, total: 0 }
          end

          def default_split
            {
              type: :split,
              left: { current: 0, total: 0 },
              right: { current: 0, total: 0 },
            }
          end

          def dynamic_mode?
            (config_reader.page_numbering_mode || :dynamic) == :dynamic
          end

          def show_page_numbers?
            config_reader.show_page_numbers
          end

          def current_view_mode
            config_reader.view_mode || :single
          end

          def current_line_spacing
            config_reader.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
          end

          def terminal_size
            terminal_service.size
          end

          def size_changed?(width, height)
            # Compare with last known dimensions from reader state
            last_width = reader_state_reader.respond_to?(:last_width) ? reader_state_reader.last_width : nil
            last_height = reader_state_reader.respond_to?(:last_height) ? reader_state_reader.last_height : nil
            width != last_width || height != last_height
          end

          def current_page_index
            reader_state_reader.current_page_index.to_i
          end

          def total_pages_from_calculator
            total = page_calculator.total_pages.to_i
            total.positive? ? total : 0
          end

          def total_pages_from_state
            reader_state_reader.total_pages.to_i
          end

          def page_map_from_state
            Array(reader_state_reader.page_map || [])
          end

          def pages_before_current_chapter(page_map)
            current_chapter = reader_state_reader.current_chapter.to_i
            page_map[0...current_chapter].sum
          end

          def page_in_chapter_for_offset(line_offset, lines_per_page)
            (line_offset.to_f / lines_per_page).floor + 1
          end

          def line_offset_for_view(view_mode)
            if view_mode == :split
              reader_state_reader.left_page
            else
              reader_state_reader.single_page
            end
          end

          def absolute_layout(view_mode)
            height, width = terminal_size
            _, content_height = layout_service.calculate_metrics(width, height, view_mode)
            lines_per_page = layout_service.adjust_for_line_spacing(content_height, current_line_spacing)
            { width: width, height: height, lines_per_page: lines_per_page }
          end

          def page_map_empty?
            page_map_from_state.empty?
          end
        end
      end
    end
  end
end
