# frozen_string_literal: true

require_relative '../../../terminal/text_metrics'

module Shoko
  module Adapters::Output::Formatting
    class FormattingService
      class LineAssembler
        # Renders table blocks into box-drawn display lines.
        class TableRenderer
          include Shoko::Core::Models
          ALIGNMENT_MAP = {
            'left' => :left,
            'right' => :right,
            'center' => :center,
            'middle' => :center,
            'justify' => :justify,
            'start' => :left,
            'end' => :right,
          }.freeze

          Cell = Struct.new(:text, :header, :align, :row, :col, :rowspan, :colspan, keyword_init: true)
          private_constant :Cell

          def initialize(width)
            @width = width.to_i
          end

          def render(table_data, base_metadata:)
            rows = normalize_rows(table_data)
            return [] if rows.empty?

            grid, row_count, col_count = build_grid(rows)
            return [] if row_count.zero? || col_count.zero?

            col_widths = compute_column_widths(grid, col_count)
            return [] if col_widths.nil?

            segment_widths = col_widths.map { |w| w + 2 }
            row_v_borders = build_row_vertical_borders(grid, row_count, col_count)
            metadata = base_metadata.merge(block_type: :table)

            lines = []
            lines << boundary_line(-1, grid, row_v_borders, segment_widths, row_count, col_count, metadata)
            row_count.times do |row_index|
              lines.concat(render_row_lines(row_index, grid, col_widths, metadata))
              lines << boundary_line(row_index, grid, row_v_borders, segment_widths, row_count, col_count, metadata)
            end
            lines
          end

          private

          def normalize_rows(table_data)
            return [] unless table_data

            rows = if table_data.is_a?(Hash)
                     table_data[:rows] || table_data['rows']
                   else
                     table_data
                   end
            return [] unless rows.is_a?(Array)

            rows.map do |row|
              if row.is_a?(Hash)
                row_cells = row[:cells] || row['cells'] || []
                row_header = !!(row[:header] || row['header'])
                row_align = normalize_alignment(row[:align] || row['align'])
                cells = row_cells.map { |cell| normalize_cell(cell, row_header, row_align) }
                row_header ||= cells.any? { |cell| cell[:header] }
                { header: row_header, cells: cells, align: row_align }
              elsif row.is_a?(Array)
                cells = row.map { |value| normalize_cell({ text: value }, false, nil) }
                { header: false, cells: cells, align: nil }
              else
                cells = row.to_s.split(/\s*\|\s*/).map { |value| normalize_cell({ text: value }, false, nil) }
                { header: false, cells: cells, align: nil }
              end
            end
          end

          def normalize_cell(cell, row_header, row_align)
            return { text: '', header: row_header, colspan: 1, rowspan: 1 } unless cell

            if cell.is_a?(Hash)
              {
                text: (cell[:text] || cell['text']).to_s,
                header: row_header || cell[:header] || cell['header'],
                align: normalize_alignment(cell[:align] || cell['align'] || row_align),
                colspan: positive_int_or_one(cell[:colspan] || cell['colspan']),
                rowspan: positive_int_or_one(cell[:rowspan] || cell['rowspan']),
              }
            else
              { text: cell.to_s, header: row_header, align: row_align, colspan: 1, rowspan: 1 }
            end
          end

          def positive_int_or_one(value)
            num = value.to_i
            num.positive? ? num : 1
          end

          def build_grid(rows)
            grid = []
            rows.each_with_index do |row, row_index|
              grid[row_index] ||= []
              col_index = 0

              Array(row[:cells]).each do |cell_data|
                col_index += 1 while grid[row_index][col_index]
              cell = Cell.new(
                text: cell_data[:text].to_s,
                header: !!cell_data[:header],
                align: normalize_alignment(cell_data[:align]),
                row: row_index,
                col: col_index,
                rowspan: positive_int_or_one(cell_data[:rowspan]),
                colspan: positive_int_or_one(cell_data[:colspan])
              )

                (0...cell.rowspan).each do |row_offset|
                  target_row = row_index + row_offset
                  grid[target_row] ||= []
                  (0...cell.colspan).each do |col_offset|
                    grid[target_row][col_index + col_offset] = cell
                  end
                end

                col_index += cell.colspan
              end
            end

            row_count = grid.length
            col_count = grid.map(&:length).max.to_i

            row_count.times do |r|
              grid[r] ||= []
              (0...col_count).each do |c|
                next if grid[r][c]

                grid[r][c] = Cell.new(text: '', header: false, align: nil, row: r, col: c, rowspan: 1, colspan: 1)
              end
            end

            [grid, row_count, col_count]
          end

          def compute_column_widths(grid, col_count)
            available = @width - ((3 * col_count) + 1)
            return nil if available < col_count

            col_widths = Array.new(col_count, 1)

            grid.each do |row|
              row.each_with_index do |cell, col|
                next unless cell&.col == col && cell.colspan == 1

                width = cell_max_width(cell)
                col_widths[col] = [col_widths[col], width].max
              end
            end

            total = col_widths.sum
            return col_widths if total <= available

            over = total - available
            while over.positive?
              idx = col_widths.each_index.max_by { |i| col_widths[i] }
              break if col_widths[idx] <= 1

              col_widths[idx] -= 1
              over -= 1
            end

            col_widths
          end

          def cell_max_width(cell)
            lines = cell.text.to_s.split(/\r?\n/, -1)
            lines.map { |line| Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(line) }.max.to_i
          end

          def build_row_vertical_borders(grid, row_count, col_count)
            Array.new(row_count) do |row_index|
              borders = Array.new(col_count + 1, true)
              borders[0] = true
              borders[col_count] = true
              (1...col_count).each do |col|
                borders[col] = grid[row_index][col - 1] != grid[row_index][col]
              end
              borders
            end
          end

          def render_row_lines(row_index, grid, col_widths, metadata)
            render_cells = build_render_cells(row_index, grid, col_widths)
            height = render_cells.map { |cell| cell[:lines].length }.max.to_i
            height = 1 if height <= 0

            lines = []
            height.times do |line_index|
              segments = []
              text = +''
              append_segment(segments, text, '│', {})

              render_cells.each do |cell|
                content = cell[:lines][line_index] || ''
                padded = align_cell_text(content, cell[:content_width], cell[:align])
                styles = cell[:header] ? { bold: true } : {}
                append_segment(segments, text, " #{padded} ", styles)
                append_segment(segments, text, '│', {})
              end

              lines << DisplayLine.new(text: text, segments: segments, metadata: metadata)
            end
            lines
          end

          def build_render_cells(row_index, grid, col_widths)
            col_count = col_widths.length
            cells = []
            col = 0
            while col < col_count
              cell = grid[row_index][col]
              if cell && cell.col < col
                col += 1
                next
              end

              cell ||= Cell.new(text: '', header: false, align: nil, row: row_index, col: col, rowspan: 1,
                                colspan: 1)
              span = positive_int_or_one(cell.colspan)
              content_width = span_content_width(col_widths, col, span)
              text = cell.row == row_index ? cell.text.to_s : ''
              lines = wrap_cell_text(text, content_width)

              cells << {
                start_col: col,
                end_col: col + span,
                span: span,
                content_width: content_width,
                lines: lines,
                header: cell.header,
                align: normalize_alignment(cell.align),
              }
              col += span
            end
            cells
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
              wrapped = Shoko::Adapters::Output::Terminal::TextMetrics.wrap_plain_text(raw, width)
              lines.concat(wrapped)
            end
            lines = [''] if lines.empty?
            lines
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

          def normalize_alignment(value)
            return value if value.is_a?(Symbol)

            raw = value.to_s.strip.downcase
            return nil if raw.empty?

            normalized = raw.sub(/;+\z/, '')
            normalized = normalized.sub(/\s*!important\z/, '').strip
            ALIGNMENT_MAP[normalized]
          end

          def boundary_line(boundary_index, grid, row_v_borders, segment_widths, row_count, col_count, metadata)
            h_segments = horizontal_segments(boundary_index, grid, row_count, col_count)
            up = boundary_index >= 0 ? row_v_borders[boundary_index] : Array.new(col_count + 1, false)
            down = (boundary_index + 1) < row_count ? row_v_borders[boundary_index + 1] : Array.new(col_count + 1, false)

            text = +''
            segments = []

            (0..col_count).each do |col|
              left = col.positive? ? h_segments[col - 1] : false
              right = col < col_count ? h_segments[col] : false
              char = junction_char(up: up[col], down: down[col], left: left, right: right)
              append_segment(segments, text, char, {})

              next if col == col_count

              segment_char = h_segments[col] ? '─' : ' '
              append_segment(segments, text, segment_char * segment_widths[col], {})
            end

            DisplayLine.new(text: text, segments: segments, metadata: metadata)
          end

          def horizontal_segments(boundary_index, grid, row_count, col_count)
            return Array.new(col_count, true) if boundary_index.negative? || boundary_index >= row_count - 1

            Array.new(col_count) { |col| grid[boundary_index][col] != grid[boundary_index + 1][col] }
          end

          def junction_char(up:, down:, left:, right:)
            return '┼' if up && down && left && right
            return '┤' if up && down && left
            return '├' if up && down && right
            return '┴' if up && left && right
            return '┬' if down && left && right
            return '┘' if up && left
            return '└' if up && right
            return '┐' if down && left
            return '┌' if down && right
            return '│' if up || down
            return '─' if left || right

            ' '
          end

          def append_segment(segments, text, value, styles)
            return if value.to_s.empty?

            text << value
            if segments.empty? || segments.last.styles != styles
              segments << TextSegment.new(text: value, styles: styles)
            else
              segments[-1] = TextSegment.new(text: segments[-1].text + value, styles: styles)
            end
          end
        end
      end
    end
  end
end
