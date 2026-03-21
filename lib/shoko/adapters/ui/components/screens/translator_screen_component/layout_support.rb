# frozen_string_literal: true

require_relative '../../ui/box_drawer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Layout and hit-test helpers for the translator screen.
          module TranslatorScreenComponentLayoutSupport
            private

            def within_header?(box, column, row)
              row.between?(box.row + 1, box.row + 2) && within_column_range?(box, column)
            end

            def within_dropdown?(box, column, row, kind)
              window = dropdown_window(kind)
              item_count = dropdown_row_count(window)
              return false if item_count.zero?

              popup_box = dropdown_popup_box(box, kind)
              first_row = dropdown_item_start_row(popup_box)
              last_row = first_row + item_count - 1
              min_col = popup_box.col + 1
              max_col = popup_box.col + popup_box.width - 2
              column.between?(min_col, max_col) && row.between?(first_row, last_row)
            end

            def within_body?(box, column, row, kind)
              within_column_range?(box, column) && row.between?(body_start_row(box, kind), box.row + box.height - 2)
            end

            def within_column_range?(box, column)
              column.between?(box.col + 2, box.col + box.width - 3)
            end

            def body_start_row(box, _kind)
              box.row + 5
            end

            def body_height(box, kind)
              used_rows = body_start_row(box, kind) - box.row
              [box.height - used_rows - 1, 1].max
            end

            def body_width(box)
              [box.width - 4, 8].max
            end

            def dropdown_row_count(window)
              items = Array(window[:items])
              items.empty? ? 1 : items.length
            end

            def layout_metrics(bounds)
              content_width = content_width_for(bounds)
              left_width = (content_width / 2) - 1
              right_width = content_width - left_width - 2
              indent = [(bounds.width - content_width) / 2, 2].max
              height = box_height_for(bounds)
              top_row = top_row_for(bounds, height)
              widths = { left: left_width, right: right_width }
              { indent: indent, status_row: 4, content_width: content_width }.merge(
                translator_panel_boxes(top_row: top_row, indent: indent, widths: widths, height: height)
              )
            end

            def content_width_for(bounds)
              [bounds.width - 6, 96].min.clamp(44, 96)
            end

            def box_height_for(bounds)
              preferred = [bounds.height - 14, 14].max
              max_height = bounds.height - 8
              [preferred, max_height].min
            end

            def top_row_for(bounds, height)
              [(bounds.height - height) / 2, 6].max
            end

            def translator_panel_boxes(top_row:, indent:, widths:, height:)
              {
                left_box: Ui::BoxDrawer::BoxSpec.new(row: top_row, col: indent, width: widths[:left], height: height),
                right_box: Ui::BoxDrawer::BoxSpec.new(
                  row: top_row,
                  col: indent + widths[:left] + 2,
                  width: widths[:right],
                  height: height
                ),
              }
            end
          end
        end
      end
    end
  end
end
