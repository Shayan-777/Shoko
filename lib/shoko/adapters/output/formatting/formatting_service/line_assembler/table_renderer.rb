# frozen_string_literal: true

require_relative '../../../terminal/text_metrics'
require_relative '../../../../../core/models/content_block'
require_relative 'table_renderer/normalization_support'
require_relative 'table_renderer/grid_support'
require_relative 'table_renderer/row_rendering_support'
require_relative 'table_renderer/boundary_rendering_support'

module Shoko
  module Adapters
    module Output
      module Formatting
        class FormattingService
          class LineAssembler
            # Renders table blocks into box-drawn display lines.
            class TableRenderer
              include Shoko::Core::Models
              include NormalizationSupport
              include GridSupport
              include RowRenderingSupport
              include BoundaryRenderingSupport

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
            end
          end
        end
      end
    end
  end
end
