# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Rendering
        module Models
          # Represents the geometry for a rendered line on screen. Holds the plain
          # text, ANSI-styled text, and per-cell breakdown so selections/tooltips can
          # share the same layout information as the renderer.
          class LineGeometry
            attr_reader :page_id, :column_id, :row, :column_origin, :line_offset, :plain_text, :styled_text, :cells

            def initialize(page_id:, column_id:, row:, column_origin:, line_offset:,
                           plain_text:, styled_text:, cells: [])
              @page_id = page_id
              @column_id = column_id
              @row = row
              @column_origin = column_origin
              @line_offset = line_offset
              @plain_text = plain_text.to_s
              @styled_text = styled_text.to_s
              @cells = cells || []
            end

            def key
              "#{column_id}_#{line_offset}_#{row}"
            end

            def visible_width
              @visible_width ||= cells.sum(&:display_width)
            end

            def to_h
              {
                page_id:,
                column_id:,
                row:,
                column_origin:,
                line_offset:,
                plain_text:,
                styled_text:,
                visible_width:,
                cells: cells.map(&:to_h),
              }
            end
          end
        end
      end
    end
  end
end
