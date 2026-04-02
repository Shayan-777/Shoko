# frozen_string_literal: true

require_relative '../../../core/models/reader_settings'
require_relative '../../../core/ports/outbound/app_config_store'
require_relative '../../../core/ports/outbound/reader_session_store'
require_relative '../../../core/ports/outbound/reader_runtime_context'
require_relative 'page_info_calculator/absolute_mode_support'

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
          include PageInfoCalculatorAbsoluteModeSupport

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
        end
      end
    end
  end
end
