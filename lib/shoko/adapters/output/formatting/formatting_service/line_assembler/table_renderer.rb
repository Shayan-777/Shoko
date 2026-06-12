# frozen_string_literal: true

require_relative '../../../terminal/text_metrics'
require_relative '../../../../../core/models/content_block'

module Shoko
  module Adapters
    module Output
      module Formatting
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
              JUNCTION_CHARS = {
                15 => '┼',
                14 => '┤',
                13 => '├',
                11 => '┴',
                7 => '┬',
                10 => '┘',
                9 => '└',
                6 => '┐',
                5 => '┌',
                12 => '│',
                8 => '│',
                4 => '│',
                3 => '─',
                2 => '─',
                1 => '─',
              }.freeze

              Cell = Struct.new(:text, :header, :align, :row, :col, :rowspan, :colspan)
              private_constant :Cell

              def initialize(width)
                @width = width.to_i
              end

              def render(table_data, base_metadata:)
                rows = normalize_rows(table_data)
                return [] if rows.empty?

                grid, row_count, col_count = build_grid(rows)
                col_widths = column_widths_for(grid, row_count, col_count)
                return [] if col_widths.nil?

                render_lines(
                  grid: grid,
                  row_count: row_count,
                  col_count: col_count,
                  col_widths: col_widths,
                  base_metadata: base_metadata
                )
              end

              private

              def column_widths_for(grid, row_count, col_count)
                return nil if row_count.zero? || col_count.zero?

                compute_column_widths(grid, col_count)
              end

              def render_lines(grid:, row_count:, col_count:, col_widths:, base_metadata:)
                context = boundary_context(
                  grid: grid,
                  row_count: row_count,
                  col_count: col_count,
                  col_widths: col_widths,
                  base_metadata: base_metadata
                )
                lines = [boundary_line(-1, context)]

                row_count.times do |row_index|
                  lines.concat(render_row_lines(row_index, grid, col_widths, context[:metadata]))
                  lines << boundary_line(row_index, context)
                end

                lines
              end

              def boundary_context(grid:, row_count:, col_count:, col_widths:, base_metadata:)
                {
                  grid: grid,
                  row_count: row_count,
                  col_count: col_count,
                  segment_widths: col_widths.map { |width| width + 2 },
                  row_v_borders: build_row_vertical_borders(grid, row_count, col_count),
                  metadata: base_metadata.merge(block_type: :table),
                }
              end

              # Computes table border junctions and emits boundary display lines.
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

              def boundary_line(boundary_index, context)
                horizontal = horizontal_segments(
                  boundary_index,
                  context[:grid],
                  context[:row_count],
                  context[:col_count]
                )
                upward = boundary_borders(boundary_index, context[:row_v_borders], context[:col_count])
                downward = boundary_borders(boundary_index + 1, context[:row_v_borders], context[:col_count])

                build_boundary_display_line(context, horizontal, upward, downward)
              end

              def build_boundary_display_line(context, horizontal_segments, upward_borders, downward_borders)
                text = +''
                segments = []
                buffers = { segments: segments, text: text }
                borders = { up: upward_borders, down: downward_borders }
                append_boundary_columns(context, horizontal_segments, borders, buffers)
                build_display_line(text, segments, context[:metadata])
              end

              def append_boundary_column(segments:, text:, col:, col_count:, h_segments:, up_borders:, down_borders:,
                                         segment_widths:)
                append_boundary_junction(
                  segments: segments,
                  text: text,
                  col: col,
                  col_count: col_count,
                  h_segments: h_segments,
                  up_borders: up_borders,
                  down_borders: down_borders
                )
                return if col == col_count

                append_boundary_segment(segments, text, h_segments[col], segment_widths[col])
              end

              def append_boundary_junction(
                segments:,
                text:,
                col:,
                col_count:,
                h_segments:,
                up_borders:,
                down_borders:
              )
                leftward = col.positive? ? h_segments[col - 1] : false
                rightward = col < col_count ? h_segments[col] : false
                char = junction_char(
                  upward: up_borders[col],
                  downward: down_borders[col],
                  leftward: leftward,
                  rightward: rightward
                )
                append_segment(segments, text, char, {})
              end

              def append_boundary_segment(segments, text, has_boundary, width)
                segment_char = has_boundary ? '─' : ' '
                append_segment(segments, text, segment_char * width, {})
              end

              def append_boundary_columns(context, horizontal_segments, borders, buffers)
                (0..context[:col_count]).each do |col|
                  append_boundary_column(
                    segments: buffers[:segments],
                    text: buffers[:text],
                    col: col,
                    col_count: context[:col_count],
                    h_segments: horizontal_segments,
                    up_borders: borders[:up],
                    down_borders: borders[:down],
                    segment_widths: context[:segment_widths]
                  )
                end
              end

              def build_display_line(text, segments, metadata)
                Shoko::Application::Ports::Outbound::Formatting::DisplayLine.new(text: text, segments: segments,
                                                                                 metadata: metadata)
              end

              def boundary_borders(index, row_v_borders, col_count)
                return Array.new(col_count + 1, false) if index.negative? || index >= row_v_borders.length

                row_v_borders[index]
              end

              def horizontal_segments(boundary_index, grid, row_count, col_count)
                return Array.new(col_count, true) if boundary_index.negative? || boundary_index >= row_count - 1

                Array.new(col_count) { |col| grid[boundary_index][col] != grid[boundary_index + 1][col] }
              end

              def junction_char(upward:, downward:, leftward:, rightward:)
                mask = 0
                mask |= 8 if upward
                mask |= 4 if downward
                mask |= 2 if leftward
                mask |= 1 if rightward

                JUNCTION_CHARS.fetch(mask, ' ')
              end

              def append_segment(segments, text, value, styles)
                return if value.to_s.empty?

                text << value
                if segments.empty? || segments.last.styles != styles
                  segments << Shoko::Core::Models::TextSegment.new(text: value, styles: styles)
                else
                  previous = segments[-1]
                  segments[-1] = Shoko::Core::Models::TextSegment.new(text: previous.text + value, styles: styles)
                end
              end

              # Builds spanning-cell grids and computes per-column widths.
              def build_grid(rows)
                grid = []
                rows.each_with_index { |row, row_index| populate_grid_row(grid, row, row_index) }
                row_count = grid.length
                col_count = grid.map(&:length).max.to_i
                fill_missing_grid_cells(grid, row_count, col_count)
                [grid, row_count, col_count]
              end

              def populate_grid_row(grid, row, row_index)
                grid[row_index] ||= []
                col_index = 0
                Array(row[:cells]).each do |cell_data|
                  col_index = next_open_col(grid, row_index, col_index)
                  cell = build_grid_cell(cell_data, row_index, col_index)
                  populate_grid_span(grid, cell)
                  col_index += cell.colspan
                end
              end

              def next_open_col(grid, row_index, col_index)
                col_index += 1 while grid[row_index][col_index]
                col_index
              end

              def build_grid_cell(cell_data, row_index, col_index)
                Cell.new(
                  text: cell_data[:text].to_s,
                  header: truthy?(cell_data[:header]),
                  align: normalize_alignment(cell_data[:align]),
                  row: row_index,
                  col: col_index,
                  rowspan: positive_int_or_one(cell_data[:rowspan]),
                  colspan: positive_int_or_one(cell_data[:colspan])
                )
              end

              def populate_grid_span(grid, cell)
                (0...cell.rowspan).each do |row_offset|
                  target_row = cell.row + row_offset
                  grid[target_row] ||= []
                  (0...cell.colspan).each do |col_offset|
                    grid[target_row][cell.col + col_offset] = cell
                  end
                end
              end

              def fill_missing_grid_cells(grid, row_count, col_count)
                row_count.times do |row_index|
                  grid[row_index] ||= []
                  (0...col_count).each do |col_index|
                    grid[row_index][col_index] ||= empty_cell(row_index, col_index)
                  end
                end
              end

              def empty_cell(row_index, col_index)
                Cell.new(text: '', header: false, align: nil, row: row_index, col: col_index, rowspan: 1, colspan: 1)
              end

              def compute_column_widths(grid, col_count)
                available = available_cell_width(col_count)
                return nil if available < col_count

                col_widths = preferred_column_widths(grid, col_count)
                shrink_column_widths(col_widths, available)
              end

              def available_cell_width(col_count)
                @width - ((3 * col_count) + 1)
              end

              def preferred_column_widths(grid, col_count)
                widths = Array.new(col_count, 1)
                grid.each { |row| apply_row_widths!(widths, row) }
                widths
              end

              def apply_row_widths!(widths, row)
                row.each_with_index do |cell, col_index|
                  next unless cell&.col == col_index && cell.colspan == 1

                  widths[col_index] = [widths[col_index], cell_max_width(cell)].max
                end
              end

              def shrink_column_widths(col_widths, available)
                extra = col_widths.sum - available
                while extra.positive?
                  widest_index = col_widths.each_index.max_by { |index| col_widths[index] }
                  break if col_widths[widest_index] <= 1

                  col_widths[widest_index] -= 1
                  extra -= 1
                end
                col_widths
              end

              def cell_max_width(cell)
                lines = cell.text.to_s.split(/\r?\n/, -1)
                lines.map { |line| Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(line) }.max.to_i
              end

              # Normalizes raw table metadata rows/cells into renderer-ready hashes.
              def normalize_rows(table_data)
                rows = extract_rows(table_data)
                return [] unless rows.is_a?(Array)

                rows.map { |row| normalize_row(row) }
              end

              def extract_rows(table_data)
                return nil unless table_data
                return symbolize_hash(table_data)[:rows] if table_data.is_a?(Hash)

                table_data
              end

              def normalize_row(row)
                return normalize_hash_row(row) if row.is_a?(Hash)
                return normalize_array_row(row) if row.is_a?(Array)

                normalize_delimited_row(row)
              end

              def normalize_hash_row(row)
                normalized = symbolize_hash(row)
                row_cells = normalized[:cells] || []
                row_header = truthy?(normalized[:header])
                row_align = normalize_alignment(normalized[:align])
                cells = row_cells.map { |cell| normalize_cell(cell, row_header, row_align) }
                row_header ||= cells.any? { |cell| cell[:header] }
                { header: row_header, cells: cells, align: row_align }
              end

              def normalize_array_row(row)
                cells = row.map { |value| normalize_cell({ text: value }, false, nil) }
                { header: false, cells: cells, align: nil }
              end

              def normalize_delimited_row(row)
                cells = row.to_s.split(/\s*\|\s*/).map { |value| normalize_cell({ text: value }, false, nil) }
                { header: false, cells: cells, align: nil }
              end

              def normalize_cell(cell, row_header, row_align)
                return { text: '', header: row_header, colspan: 1, rowspan: 1 } unless cell
                return normalize_hash_cell(cell, row_header, row_align) if cell.is_a?(Hash)

                { text: cell.to_s, header: row_header, align: row_align, colspan: 1, rowspan: 1 }
              end

              def normalize_hash_cell(cell, row_header, row_align)
                normalized = symbolize_hash(cell)
                {
                  text: normalized[:text].to_s,
                  header: row_header || truthy?(normalized[:header]),
                  align: normalize_alignment(normalized[:align] || row_align),
                  colspan: positive_int_or_one(normalized[:colspan]),
                  rowspan: positive_int_or_one(normalized[:rowspan]),
                }
              end

              def truthy?(value)
                !value.nil? && value != false
              end

              def positive_int_or_one(value)
                number = value.to_i
                number.positive? ? number : 1
              end

              def symbolize_hash(value)
                value.transform_keys do |key|
                  key.is_a?(String) ? key.to_sym : key
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

              # Renders row bodies and cell content into display lines.
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
                Shoko::Application::Ports::Outbound::Formatting::DisplayLine.new(text: text, segments: segments,
                                                                                 metadata: metadata)
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
