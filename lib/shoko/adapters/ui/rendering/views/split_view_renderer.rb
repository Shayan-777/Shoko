# frozen_string_literal: true

require_relative 'base_view_renderer'
require_relative '../../components/render_style'
require_relative '../../../../application/ports/outbound/formatting/display_line'

module Shoko
  module Adapters
    module Ui
      module Components
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
              :divider_col
            )

            # Encapsulates per-render state shared across helpers.
            RenderFrame = Struct.new(:surface, :bounds, :context, :layout)

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
              layout = split_layout(bounds, context.config_reader)
              frame = RenderFrame.new(surface: surface, bounds: bounds, context: context, layout: layout)
              render_chapter_header(frame)
              sidebar_visible = context.reader_state_reader&.sidebar_visible? == true

              left_pd = context.page_calculator&.get_page(
                context.current_page_index,
                width: bounds.width,
                height: bounds.height,
                sidebar_visible: sidebar_visible
              )
              if left_pd
                render_dynamic_from_page_data(frame, left_pd)
              else
                render_dynamic_fallback(frame)
              end
            end

            def render_absolute_mode_with_context(surface, bounds, context)
              chapter = context.current_chapter
              return unless chapter

              reader = context&.reader_state_reader
              return unless reader

              layout = split_layout(bounds, context.config_reader)
              frame = RenderFrame.new(surface: surface, bounds: bounds, context: context, layout: layout)
              render_chapter_header(frame)

              layout.displayable
              left_offset = reader.left_page
              right_offset = reader.right_page
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
              clipped = Shoko::Shared::Terminal::TextMetrics.truncate_to(info, available, start_column: start_column)
              heading_color = Shoko::Adapters::Ui::Components::RenderStyle.color(:heading)
              heading_color + clipped + Shoko::Shared::Terminal::Ansi::RESET
            end

            def render_dynamic_from_page_data(frame, left_page_data)
              page_id = frame.context.current_page_index
              render_page_data_column(frame, left_page_data, dynamic_column_spec(frame.layout.left_start, 0, page_id))
              draw_divider(frame.surface, frame.bounds, frame.layout.divider_col)

              right_page_data = next_dynamic_page_data(frame, page_id)
              return unless right_page_data

              render_page_data_column(frame,
                                      right_page_data,
                                      dynamic_column_spec(frame.layout.right_start, 1, next_page_id(page_id)))
            end

            def render_dynamic_fallback(frame)
              layout = frame.layout
              page_id = frame.context.current_page_index
              right_page_id = page_id ? page_id + 1 : nil

              displayable = layout.displayable
              base_offset = (page_id || 0) * [displayable, 1].max

              render_offset_column(frame, base_offset, { start_col: layout.left_start, column_id: 0, page_id: page_id })
              draw_divider(frame.surface, frame.bounds, layout.divider_col)

              render_offset_column(frame,
                                   base_offset + displayable,
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
              render_offset_column(frame,
                                   right_input,
                                   { start_col: layout.right_start, column_id: 1, page_id: page_id })
            end

            def fetch_wrapped_lines_window(frame, offset, length)
              chapter_index = frame.context.reader_state_reader&.current_chapter || 0
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

              if lines.nil? || lines.empty? || !lines_fit_column?(lines, frame.layout.col_width)
                return fetch_wrapped_lines_window(frame, line_offset, span_length)
              end

              snapped = snap_offset_to_image_start(lines, line_offset)
              return [lines, line_offset] if snapped == line_offset

              fetch_wrapped_lines_window(frame, snapped, span_length)
            end

            def render_page_data_column(frame, page_data, column_spec)
              lines, line_offset = column_lines_from_page_data(frame, page_data)
              render_column_lines(frame, lines, column_params(frame, column_spec, line_offset))
            end

            def dynamic_column_spec(start_col, column_id, page_id)
              { start_col: start_col, column_id: column_id, page_id: page_id }
            end

            def next_page_id(page_id)
              page_id ? page_id + 1 : nil
            end

            def next_dynamic_page_data(frame, page_id)
              return nil unless page_id

              frame.context.page_calculator&.get_page(
                page_id + 1,
                width: frame.bounds.width,
                height: frame.bounds.height,
                sidebar_visible: frame.context.reader_state_reader&.sidebar_visible? == true
              )
            end

            def column_params(frame, column_spec, line_offset)
              Adapters::Ui::Rendering::Models::RenderParams.new(
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

            def lines_fit_column?(lines, col_width)
              width = col_width.to_i
              return true if width <= 0

              Array(lines).first(6).all? do |line|
                next true unless line
                next true if image_line?(line)

                text = line.is_a?(Shoko::Application::Ports::Outbound::Formatting::DisplayLine) ? line.text.to_s : line.to_s
                Shoko::Shared::Terminal::TextMetrics.visible_length(text) <= width
              end
            end

            def image_line?(line)
              return false unless line.is_a?(Shoko::Application::Ports::Outbound::Formatting::DisplayLine)

              meta = line.metadata
              return false unless meta.is_a?(Hash)

              block_type = meta[:block_type]
              block_type == :image || block_type.to_s == 'image'
            end
          end
        end
      end
    end
  end
end
