# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # List rendering helpers for the settings master panel.
          module SettingsScreenComponentListRenderer
            SettingRow = Data.define(:row, :item, :selected, :columns, :indent)

            private

            def render_settings_list(surface, bounds, panel, selected)
              columns = list_columns(panel.width)
              render_settings_header(surface, bounds, panel, columns)

              setting_rows(panel, selected, columns).each do |row|
                render_settings_row(surface, bounds, row)
              end
            end

            def render_settings_header(surface, bounds, panel, columns)
              MenuDesign::TableRenderer.new(surface, bounds).render_header(
                row: panel.y,
                indent: panel.x,
                headers: %w[Setting Value],
                widths: [columns[:label], columns[:value]],
                divider_char: '─'
              )
            end

            def setting_rows(panel, selected, columns)
              visible_rows = [panel.height - 2, 0].max
              return [] if visible_rows <= 0

              slice = visible_setting_slice(selected, visible_rows)
              slice[:items].each_with_index.filter_map do |item, offset|
                build_setting_row(panel: panel, columns: columns, selected: selected, item: item, offset: offset,
                                  start_index: slice[:start_index])
              end
            end

            def build_setting_row(panel:, columns:, selected:, start_index:, item:, offset:)
              row = panel.y + 2 + offset
              return nil if row > panel.bottom

              SettingRow.new(
                row: row,
                item: item,
                selected: (start_index + offset) == selected,
                columns: columns,
                indent: panel.x
              )
            end

            def visible_setting_slice(selected, visible_rows)
              start_index, items = Ui::ListHelpers.slice_visible(
                SettingsScreenComponent::SETTINGS_ITEMS,
                visible_rows,
                selected
              )
              { start_index: start_index, items: items }
            end

            def render_settings_row(surface, bounds, row)
              value_text, = display_value_for(row.item.action)
              MenuDesign::TableRenderer.new(surface, bounds).render_row(
                row: row.row,
                indent: row.indent,
                cells: setting_row_cells(row, value_text),
                widths: [row.columns[:label], row.columns[:value]],
                selected: row.selected
              )
            end

            def setting_row_cells(row, value_text)
              [
                pad_right(truncate_text(label_text(row.item), row.columns[:label]), row.columns[:label]),
                pad_right(truncate_text(value_text, row.columns[:value]), row.columns[:value]),
              ]
            end

            def list_columns(width)
              gap = 3
              value_width = (width / 3).clamp(12, 18)
              { label: [width - value_width - gap, 18].max, value: value_width }
            end
          end
        end
      end
    end
  end
end
