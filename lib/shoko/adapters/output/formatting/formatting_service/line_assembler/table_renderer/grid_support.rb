# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Formatting
        class FormattingService
          class LineAssembler
            class TableRenderer
              # Builds spanning-cell grids and computes per-column widths.
              module GridSupport
                private

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
              end
            end
          end
        end
      end
    end
  end
end
