# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Formatting
        class FormattingService
          class LineAssembler
            class TableRenderer
              # Renders row bodies and cell content into display lines.
              module RowRenderingSupport
                private

                def render_row_lines(row_index, grid, col_widths, metadata)
                  render_cells = build_render_cells(row_index, grid, col_widths)
                  row_height = [render_cells.map { |cell| cell[:lines].length }.max.to_i, 1].max

                  Array.new(row_height) do |line_index|
                    render_row_line(render_cells, line_index, metadata)
                  end
                end

                def render_row_line(render_cells, line_index, metadata)
                  text = +''
                  segments = []
                  append_segment(segments, text, '│', {})
                  render_cells.each do |cell|
                    append_cell_content(segments, text, cell, line_index)
                  end
                  Shoko::Core::Models::DisplayLine.new(text: text, segments: segments, metadata: metadata)
                end

                def append_cell_content(segments, text, cell, line_index)
                  content = cell[:lines][line_index] || ''
                  padded = align_cell_text(content, cell[:content_width], cell[:align])
                  styles = cell[:header] ? { bold: true } : {}
                  append_segment(segments, text, " #{padded} ", styles)
                  append_segment(segments, text, '│', {})
                end

                def build_render_cells(row_index, grid, col_widths)
                  cells = []
                  col_index = 0

                  while col_index < col_widths.length
                    cell = grid[row_index][col_index]
                    if cell && cell.col < col_index
                      col_index += 1
                      next
                    end

                    render_cell = build_render_cell(row_index, col_index, col_widths, cell)
                    cells << render_cell
                    col_index += render_cell[:span]
                  end

                  cells
                end

                def build_render_cell(row_index, col_index, col_widths, cell)
                  cell ||= empty_cell(row_index, col_index)
                  span = positive_int_or_one(cell.colspan)
                  content_width = span_content_width(col_widths, col_index, span)
                  text = cell.row == row_index ? cell.text.to_s : ''

                  {
                    start_col: col_index,
                    end_col: col_index + span,
                    span: span,
                    content_width: content_width,
                    lines: wrap_cell_text(text, content_width),
                    header: cell.header,
                    align: normalize_alignment(cell.align),
                  }
                end

                def span_content_width(col_widths, start_col, span)
                  span_display_width(col_widths, start_col, span) - 2
                end

                def span_display_width(col_widths, start_col, span)
                  content_width = col_widths[start_col, span].to_a.sum
                  content_width + (2 * span) + (span - 1)
                end

                def wrap_cell_text(text, width)
                  return [''] if width <= 0

                  lines = []
                  text.to_s.split(/\r?\n/, -1).each do |raw|
                    lines.concat(Shoko::Adapters::Output::Terminal::TextMetrics.wrap_plain_text(raw, width))
                  end
                  lines.empty? ? [''] : lines
                end

                def align_cell_text(text, width, align)
                  return Shoko::Adapters::Output::Terminal::TextMetrics.pad_right(text, width) if width <= 0

                  case align
                  when :right
                    Shoko::Adapters::Output::Terminal::TextMetrics.pad_left(text, width)
                  when :center
                    Shoko::Adapters::Output::Terminal::TextMetrics.pad_center(text, width)
                  else
                    Shoko::Adapters::Output::Terminal::TextMetrics.pad_right(text, width)
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
