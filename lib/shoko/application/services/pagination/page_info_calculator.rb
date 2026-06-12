# frozen_string_literal: true

require_relative '../../../core/models/reader_settings'
require_relative '../../../application/ports/outbound/app_config_store'
require_relative '../../../application/ports/outbound/reader_session_store'
require_relative '../../../application/ports/outbound/reader_runtime_context'

module Shoko
  module Application
    module Services
      module Pagination
        # Computes reader page information (current/total pages) for single and split view modes.
        # Encapsulates sizing logic so ReaderController can delegate without duplicating calculations.
        #
        # This class follows hexagonal architecture principles:
        # - Config and reader state go through typed session stores
        # - Runtime sizing goes through ReaderRuntimeContext
        class PageInfoCalculator
          def initialize(doc:, page_calculator:, layout_service:, reader_runtime_context:,
                         pagination_runtime:, defer_page_map:,
                         app_config_store:, reader_session_store:, reader_state_reader: nil,
                         reader_view_state_store: nil, reader_pagination_store: nil)
            @doc = doc
            @page_calculator = page_calculator
            @layout_service = layout_service
            @reader_runtime_context = reader_runtime_context
            @pagination_runtime = pagination_runtime
            @defer_page_map = defer_page_map
            @app_config_store = app_config_store
            @reader_session_store = reader_session_store
            @reader_state_reader = reader_state_reader || reader_session_store
            @reader_view_state_store = reader_view_state_store || @reader_state_reader
            @reader_pagination_store = reader_pagination_store || @reader_state_reader
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

          attr_reader :doc,
                      :page_calculator,
                      :layout_service,
                      :reader_runtime_context,
                      :pagination_runtime,
                      :defer_page_map,
                      :app_config_store,
                      :reader_session_store,
                      :reader_state_reader,
                      :reader_view_state_store,
                      :reader_pagination_store

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
            (current_config.page_numbering_mode || :dynamic) == :dynamic
          end

          def show_page_numbers?
            current_config.show_page_numbers
          end

          def current_view_mode
            current_config.view_mode || :single
          end

          def current_line_spacing
            current_config.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
          end

          def terminal_size
            size = reader_runtime_context.terminal_size
            [size.height, size.width]
          end

          def size_changed?(width, height)
            reader_pagination_store.last_width.to_i != width ||
              reader_pagination_store.last_height.to_i != height
          end

          def current_page_index
            current_reader.current_page_index.to_i
          end

          def total_pages_from_calculator
            total = page_calculator.total_pages.to_i
            total.positive? ? total : 0
          end

          def total_pages_from_state
            reader_pagination_store.total_pages.to_i
          end

          def page_map_from_state
            Array(reader_pagination_store.page_map || [])
          end

          def pages_before_current_chapter(page_map)
            current_chapter = current_reader.current_chapter.to_i
            page_map[0...current_chapter].sum
          end

          def page_in_chapter_for_offset(line_offset, lines_per_page)
            (line_offset.to_f / lines_per_page).floor + 1
          end

          def current_config
            app_config_store.load
          end

          def current_reader
            reader_session_store.load
          end

          # Absolute-mode page calculations extracted from PageInfoCalculator so
          # the main service can stay focused on dispatch and shared state access.
          def calculate_absolute_single
            layout = absolute_layout(current_view_mode)
            lines_per_page = layout[:lines_per_page]
            return default_single if lines_per_page <= 0

            ensure_absolute_page_map(layout[:width], layout[:height])
            build_absolute_single_info(lines_per_page)
          end

          def calculate_absolute_split
            layout = absolute_layout(:split)
            lines_per_page = layout[:lines_per_page]
            return default_split if lines_per_page <= 0

            ensure_absolute_page_map(layout[:width], layout[:height])
            total_pages = total_pages_from_state
            return default_split unless total_pages.positive?

            build_absolute_split_info(lines_per_page, total_pages)
          end

          def ensure_absolute_page_map(width, height)
            return if defer_page_map
            return unless page_calculator
            return unless page_map_empty? || size_changed?(width, height)

            pagination_runtime&.ensure_absolute_page_map(width: width, height: height)
          end

          def build_absolute_single_info(lines_per_page)
            total_pages = total_pages_from_state

            {
              type: :single,
              current: absolute_single_page(lines_per_page),
              total: total_pages.positive? ? total_pages : 0,
            }
          end

          def absolute_single_page(lines_per_page)
            page_map = page_map_from_state
            pages_before = pages_before_current_chapter(page_map)
            pages_before + page_in_chapter_for_current_view(lines_per_page)
          end

          def page_in_chapter_for_current_view(lines_per_page)
            line_offset = line_offset_for_view(current_view_mode)
            page_in_chapter_for_offset(line_offset, lines_per_page)
          end

          def build_absolute_split_info(lines_per_page, total_pages)
            pages_before = pages_before_current_chapter(page_map_from_state)
            left_current = absolute_split_page(current_reader.left_page, lines_per_page, pages_before)
            right_current = absolute_right_page(lines_per_page, pages_before, total_pages)

            {
              type: :split,
              left: { current: left_current, total: total_pages },
              right: { current: right_current, total: total_pages },
            }
          end

          def absolute_right_page(lines_per_page, pages_before, total_pages)
            right_offset = current_reader.right_page
            right_offset = lines_per_page if right_offset.to_i.zero?
            [absolute_split_page(right_offset, lines_per_page, pages_before), total_pages].min
          end

          def absolute_split_page(line_offset, lines_per_page, pages_before)
            pages_before + page_in_chapter_for_offset(line_offset, lines_per_page)
          end

          def line_offset_for_view(view_mode)
            view_mode == :split ? current_reader.left_page : current_reader.single_page
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
