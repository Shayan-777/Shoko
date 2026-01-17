# frozen_string_literal: true

require_relative '../../../terminal/text_metrics'
require_relative '../../../rendering/models/line_geometry'

module Shoko
  module Adapters::Output::Ui::Components
    module Reading
      # Builds `Shoko::Adapters::Output::Rendering::Models::LineGeometry` objects for selection/highlighting.
      class LineGeometryBuilder
        def build(page_id:, column_id:, row:, col:, line_offset:, plain_text:, styled_text:)
          cell_data = Shoko::Adapters::Output::Terminal::TextMetrics.cell_data_for(plain_text.to_s)
          cells = cell_data.map { |cell| build_cell(cell) }

          Shoko::Adapters::Output::Rendering::Models::LineGeometry.new(
            page_id: page_id,
            column_id: column_id,
            row: row,
            column_origin: col,
            line_offset: line_offset,
            plain_text: plain_text,
            styled_text: styled_text,
            cells: cells
          )
        end

        private

        def build_cell(cell)
          Shoko::Adapters::Output::Rendering::Models::LineCell.new(
            cluster: cell[:cluster],
            char_start: cell[:char_start],
            char_end: cell[:char_end],
            display_width: cell[:display_width],
            screen_x: cell[:screen_x]
          )
        end
      end
    end
  end
end
