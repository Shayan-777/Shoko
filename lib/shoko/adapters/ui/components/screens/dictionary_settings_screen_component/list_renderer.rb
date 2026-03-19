# frozen_string_literal: true

require_relative '../../../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Rendering helpers for dictionary settings actions and result rows.
          module DictionarySettingsScreenComponentListRenderer
            UI = Adapters::Ui::Constants::Ui
            ActionRow = Data.define(:item, :row, :selected, :width, :indent)
            ResultRow = Data.define(:item, :row, :selected, :layout)

            private

            def render_settings(surface, bounds, layout)
              reset = Shoko::Shared::Terminal::Ansi::RESET
              surface.write(
                bounds,
                layout[:settings_header_row],
                layout[:indent],
                "#{UI::COLOR_TEXT_DIM}Settings#{reset}"
              )

              action_rows(bounds, layout).each { |row| render_action_row(surface, bounds, row) }
            end

            def action_rows(bounds, layout)
              action_items.each_with_index.map do |item, index|
                ActionRow.new(
                  item: item,
                  row: layout[:settings_start_row] + index,
                  selected: selected_index == index,
                  width: layout_action_width(bounds),
                  indent: layout_indent(bounds)
                )
              end
            end

            def render_action_row(surface, bounds, row)
              reset = Shoko::Shared::Terminal::Ansi::RESET
              line = format_action_line(row.item.label.to_s, row.item.value.to_s, row.width)
              styled = if row.selected
                         selected_action_text(line, reset)
                       else
                         "#{UI::COLOR_TEXT_PRIMARY} #{line} #{reset}"
                       end
              surface.write(bounds, row.row, row.indent, styled)
            end

            def selected_action_text(line, reset)
              "#{Shoko::Shared::Terminal::Ansi::BOLD}#{UI::MENU_SELECTION_BG}" \
                "#{UI::MENU_SELECTION_TEXT} #{line} #{reset}"
            end

            def render_search(surface, bounds, layout)
              MenuDesign::SearchFieldRenderer.new(surface, bounds).render(
                label: 'Search dictionaries',
                query: dictionary_query,
                cursor: dictionary_cursor,
                row: layout[:search_label_row],
                indent: layout[:indent],
                width: layout[:content_width],
                active: search_active?
              )
            end

            def render_status(surface, bounds, layout)
              row = layout[:status_row]
              return if row > bounds.bottom

              MenuDesign::StatusRenderer.new(surface, bounds).render_status(
                row: row,
                indent: layout[:indent],
                left: status_label,
                width: layout[:content_width]
              )
              render_progress(surface, bounds, layout) if dictionary_progress.positive?
            end

            def render_progress(surface, bounds, layout)
              row = layout[:progress_row]
              return if row > bounds.bottom

              MenuDesign::ProgressRenderer.new(surface, bounds).render(
                row: row,
                indent: layout[:indent],
                width: layout[:content_width],
                progress: dictionary_progress,
                filled_char: '=',
                empty_char: '-'
              )
            end

            def render_results(surface, bounds, layout)
              items = filtered_results
              return render_empty_state(surface, bounds, layout) if items.empty?

              render_results_list(surface, bounds, layout, items)
            end

            def render_empty_state(surface, bounds, layout)
              row = (bounds.height / 2).clamp(layout[:list_start_row], bounds.bottom - 2)
              surface.write(bounds, row, layout[:indent], empty_state_message)
            end

            def render_results_list(surface, bounds, layout, items)
              list_height = bounds.height - layout[:list_start_row] - 3
              return if list_height <= 0

              draw_list_header(surface, bounds, layout)
              visible_result_rows(layout, items, list_height).each do |row|
                render_dictionary_item(surface, bounds, row)
              end
            end

            def visible_result_rows(layout, items, list_height)
              selection = [selected_index - action_items.length, 0].max
              start_index, visible = Ui::ListHelpers.slice_visible(items, list_height, selection)
              visible.each_with_index.filter_map do |item, offset|
                build_result_row(layout, item, start_index, offset)
              end
            end

            def build_result_row(layout, item, start_index, offset)
              row = layout[:list_start_row] + offset
              return nil if row > layout[:footer_row] - 1

              absolute_index = start_index + offset
              ResultRow.new(
                item: item,
                row: row,
                selected: absolute_index == [selected_index - action_items.length, 0].max &&
                  selected_index >= action_items.length,
                layout: layout
              )
            end

            def render_dictionary_item(surface, bounds, row)
              columns = row.layout[:columns]
              MenuDesign::TableRenderer.new(surface, bounds).render_row(
                row: row.row,
                indent: row.layout[:indent],
                cells: build_dictionary_cells(row.item, columns),
                widths: [columns[:status], columns[:pair], columns[:size], columns[:updated], columns[:note]],
                selected: row.selected,
                pointer: true
              )
            end

            def render_footer(_surface, bounds, layout, frame:)
              row = layout[:footer_row]
              return if row > bounds.bottom

              clipped = Shoko::Shared::Terminal::TextMetrics.truncate_to(footer_text, layout[:content_width])
              frame.render_footer(text: clipped, row: row, indent: layout[:indent])
            end
          end
        end
      end
    end
  end
end
