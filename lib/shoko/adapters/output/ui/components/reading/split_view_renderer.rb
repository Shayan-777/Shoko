# frozen_string_literal: true

require_relative 'base_view_renderer'
require_relative '../render_style'

module Shoko
  module Adapters::Output::Ui::Components
    module Reading
      # Renderer for split-view (two-column) reading mode
      # Supports both dynamic and absolute page numbering modes
      class SplitViewRenderer < BaseViewRenderer
        COLUMN_START_ROW = 3

        # Layout metrics for split-view rendering.
        SplitLayout = Struct.new(
          :col_width,
          :content_height,
          :spacing,
          :displayable,
          :left_start,
          :right_start,
          :divider_col,
          keyword_init: true
        )

        # Encapsulates per-render state shared across helpers.
        RenderFrame = Struct.new(:surface, :bounds, :context, :layout, keyword_init: true)

        private_constant :SplitLayout, :RenderFrame

        def render_with_context(surface, bounds, context)
          mode = context.page_numbering_mode || :dynamic
          if mode == :dynamic
            render_dynamic_mode_with_context(surface, bounds, context)
          else
            render_absolute_mode_with_context(surface, bounds, context)
          end
        end

        private

        # Divider provided by BaseViewRenderer#draw_divider

        def render_column_lines(frame, lines, params)
          draw_lines(frame.surface, frame.bounds, lines, params)
        end

        # Context-based rendering methods
        def render_dynamic_mode_with_context(surface, bounds, context)
          layout = split_layout(bounds, context.config)
          frame = RenderFrame.new(surface: surface, bounds: bounds, context: context, layout: layout)
          render_chapter_header(frame)

          left_pd = context.page_calculator&.get_page(context.current_page_index)
          if left_pd
            render_dynamic_from_page_data(frame, left_pd)
          else
            render_dynamic_fallback(frame)
          end
        end

        def render_absolute_mode_with_context(surface, bounds, context)
          chapter = context.current_chapter
          return unless chapter

          st = context&.state
          return unless st

          layout = split_layout(bounds, context.config)
          frame = RenderFrame.new(surface: surface, bounds: bounds, context: context, layout: layout)
          render_chapter_header(frame)

          display_height = layout.displayable
          left_offset = st.get(%i[reader left_page]) || 0
          right_offset = st.get(%i[reader right_page]) || display_height
          render_absolute_columns(frame, left_offset, right_offset)
        end

        def render_chapter_header(frame)
          chapter = frame.context.current_chapter
          return unless chapter

          header_col = @layout_metrics.split_left_margin + 1
          frame.surface.write(frame.bounds, 1, header_col, chapter_header_line(frame, chapter, header_col))
        end

        def chapter_header_line(frame, chapter, header_col)
          bounds = frame.bounds
          idx = (frame.context.reader_state_reader&.current_chapter || 0) + 1
          info = "[#{idx}] #{chapter.title || 'Unknown'}"
          available = bounds.width - @layout_metrics.split_left_margin - @layout_metrics.split_right_margin
          start_column = bounds.x + header_col - 2
          clipped = Shoko::Adapters::Output::Terminal::TextMetrics.truncate_to(info, available,
                                                                               start_column: start_column)
          heading_color = Shoko::Adapters::Output::Ui::Components::RenderStyle.color(:heading)
          heading_color + clipped + Terminal::ANSI::RESET
        end

        def render_dynamic_from_page_data(frame, left_page_data)
          layout = frame.layout
          context = frame.context
          page_id = context.current_page_index
          right_page_id = page_id ? page_id + 1 : nil

          render_page_data_column(frame, left_page_data,
                                  { start_col: layout.left_start, column_id: 0, page_id: page_id })
          draw_divider(frame.surface, frame.bounds, layout.divider_col)

          right_page_data = page_id ? context.page_calculator&.get_page(page_id + 1) : nil
          return unless right_page_data

          render_page_data_column(frame, right_page_data,
                                  { start_col: layout.right_start, column_id: 1, page_id: right_page_id })
        end

        def render_dynamic_fallback(frame)
          layout = frame.layout
          page_id = frame.context.current_page_index
          right_page_id = page_id ? page_id + 1 : nil

          displayable = layout.displayable
          base_offset = (page_id || 0) * [displayable, 1].max

          render_offset_column(frame, base_offset,
                               { start_col: layout.left_start, column_id: 0, page_id: page_id })
          draw_divider(frame.surface, frame.bounds, layout.divider_col)

          render_offset_column(frame, base_offset + displayable,
                               { start_col: layout.right_start, column_id: 1, page_id: right_page_id })
        end

        def render_offset_column(frame, offset, column_spec)
          displayable = frame.layout.displayable
          lines, line_offset = fetch_wrapped_lines_window(frame, offset, displayable)
          render_column_lines(frame, lines, column_params(frame, column_spec, line_offset))
          line_offset
        end

        def render_absolute_columns(frame, left_offset, right_offset)
          layout = frame.layout
          page_id = frame.context.current_page_index

          left_render_offset = render_offset_column(
            frame,
            left_offset,
            { start_col: layout.left_start, column_id: 0, page_id: page_id }
          )
          draw_divider(frame.surface, frame.bounds, layout.divider_col)

          display_height = layout.displayable
          paired = right_offset.to_i == left_offset.to_i + display_height
          right_input = paired ? left_render_offset + display_height : right_offset
          render_offset_column(frame, right_input,
                               { start_col: layout.right_start, column_id: 1, page_id: page_id })
        end

        def fetch_wrapped_lines_window(frame, offset, length)
          st = frame.context.state
          chapter_index = st.get(%i[reader current_chapter]) || 0
          fetch_wrapped_lines_with_offset(
            document: frame.context.document,
            chapter_index: chapter_index,
            col_width: frame.layout.col_width,
            offset: offset,
            length: length
          )
        end

        def column_lines_from_page_data(frame, page_data)
          line_offset = page_data[:start_line].to_i
          lines = page_data[:lines]
          end_line = page_data[:end_line].to_i
          span_length = [end_line - line_offset + 1, 1].max

          return fetch_wrapped_lines_window(frame, line_offset, span_length) if lines.nil? || lines.empty?

          snapped = snap_offset_to_image_start(lines, line_offset)
          return [lines, line_offset] if snapped == line_offset

          fetch_wrapped_lines_window(frame, snapped, span_length)
        end

        def render_page_data_column(frame, page_data, column_spec)
          lines, line_offset = column_lines_from_page_data(frame, page_data)
          render_column_lines(frame, lines, column_params(frame, column_spec, line_offset))
        end

        def column_params(frame, column_spec, line_offset)
          Adapters::Output::Rendering::Models::RenderParams.new(
            start_row: COLUMN_START_ROW,
            col_start: column_spec.fetch(:start_col),
            col_width: frame.layout.col_width,
            context: frame.context,
            column_id: column_spec.fetch(:column_id),
            line_offset: line_offset,
            page_id: column_spec[:page_id]
          )
        end

        def split_layout(bounds, config)
          col_width, content_height, spacing, displayable = compute_layout(bounds, :split, config)
          left_start = @layout_metrics.split_left_margin + 1
          right_start = left_start + col_width + @layout_metrics.split_column_gap
          divider_col = left_start + col_width + 1

          SplitLayout.new(
            col_width: col_width,
            content_height: content_height,
            spacing: spacing,
            displayable: displayable,
            left_start: left_start,
            right_start: right_start,
            divider_col: divider_col
          )
        end
      end
    end
  end
end
