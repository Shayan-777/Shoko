# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        # Absolute-mode page calculations extracted from PageInfoCalculator so
        # the main service can stay focused on dispatch and shared state access.
        module PageInfoCalculatorAbsoluteModeSupport
          private

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

            absolute_pagination_session(width, height)&.build_full_map
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

          def absolute_pagination_session(width, height)
            pagination_orchestrator.session(
              doc: doc,
              page_calculator: page_calculator,
              dimensions: [width, height],
              app_config_store: app_config_store,
              reader_session_store: reader_session_store,
              reader_view_state_store: reader_view_state_store,
              reader_pagination_store: reader_pagination_store
            )
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
