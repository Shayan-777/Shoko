# frozen_string_literal: true

require_relative '../../../../../shared/terminal/text_metrics'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Dropdown rendering helpers for the translator screen.
          module TranslatorScreenComponentDropdownSupport
            private

            def render_dropdown_trigger(surface, bounds, box, kind)
              code = selected_language_code(kind)
              name = language_name(code)
              surface.write(
                bounds,
                box.row + 2,
                box.col + 2,
                dropdown_row(
                  code: code,
                  name: name,
                  width: dropdown_trigger_width(box, code, name),
                  selected: panel_active?(kind),
                  kind: kind
                )
              )
            end

            def render_dropdown(surface, bounds, box, kind)
              popup_box = dropdown_popup_box(box, kind)
              draw_box(surface, bounds, popup_box, border_color: panel_accent(kind))
              context = {
                surface: surface,
                bounds: bounds,
                popup_box: popup_box,
                width: dropdown_inner_width(popup_box),
                scrollbar: dropdown_scrollbar(dropdown_window(kind), kind),
              }
              dropdown_rows_for(kind).each_with_index do |item, offset|
                render_dropdown_row(context, kind, item, offset)
              end
            end

            def dropdown_rows_for(kind)
              window = dropdown_window(kind)
              items = window[:items]
              return [{ code: '--', name: "No #{kind} languages", placeholder: true }] if items.empty?

              items.each_with_index.map do |item, offset|
                item.merge(
                  index: window[:start] + offset,
                  placeholder: false
                )
              end
            end

            def dropdown_window(kind)
              items = language_options(kind)
              start = [dropdown_selected - (self.class::MAX_DROPDOWN_ROWS / 2), 0].max
              max_start = [items.length - self.class::MAX_DROPDOWN_ROWS, 0].max
              resolved_start = start.clamp(0, max_start)
              {
                start: resolved_start,
                items: items.slice(resolved_start, self.class::MAX_DROPDOWN_ROWS) || [],
              }
            end

            def dropdown_trigger_width(box, _code, name)
              desired = dropdown_content_width(name)
              [desired, body_width(box)].min
            end

            def dropdown_popup_width(box, kind)
              desired = dropdown_rows_for(kind).map { |item| dropdown_content_width(item[:name]) }.max.to_i
              [(desired + 2).clamp(20, 32), body_width(box)].min
            end

            def dropdown_popup_box(box, kind)
              Ui::BoxDrawer::BoxSpec.new(
                row: dropdown_popup_row(box),
                col: box.col + 2,
                width: dropdown_popup_width(box, kind),
                height: dropdown_popup_height(kind)
              )
            end

            def dropdown_popup_row(box)
              box.row + 3
            end

            def dropdown_popup_height(kind)
              dropdown_row_count(dropdown_window(kind)) + 2
            end

            def dropdown_inner_width(popup_box)
              [popup_box.width - 2, 1].max
            end

            def dropdown_item_start_row(popup_box)
              popup_box.row + 1
            end

            def dropdown_content_width(name)
              name_width = visible_length(name.to_s)
              [self.class::DROPDOWN_CODE_WIDTH + name_width + 5, 15].max
            end

            def render_dropdown_row(context, kind, item, offset)
              context[:surface].write(
                context[:bounds],
                dropdown_item_start_row(context[:popup_box]) + offset,
                context[:popup_box].col + 1,
                dropdown_row(
                  code: item[:code],
                  name: item[:name],
                  width: context[:width],
                  selected: item[:index] == dropdown_selected,
                  kind: kind,
                  placeholder: item[:placeholder] == true,
                  scrollbar_cell: dropdown_scrollbar_cell(context[:scrollbar], offset)
                )
              )
            end

            def dropdown_row(code:, name:, width:, selected:, kind:, placeholder: false, scrollbar_cell: ' ')
              layout = dropdown_row_layout(width)
              palette = dropdown_palette(selected: selected, placeholder: placeholder, kind: kind)
              code_text = dropdown_code(code, layout[:code_width], placeholder: placeholder)
              text = Shoko::Shared::Terminal::TextMetrics.truncate_to(name.to_s, layout[:text_width])
              padding = ' ' * [layout[:text_width] - visible_length(text), 0].max

              "#{palette[:row_bg]} " \
                "#{palette[:code_fg]}#{code_text}" \
                "#{palette[:row_bg]} " \
                "#{palette[:text_fg]}#{text}#{padding}" \
                "#{palette[:scrollbar_fg]}#{scrollbar_cell}" \
                "#{palette[:row_bg]} #{reset}"
            end

            def dropdown_row_layout(width)
              inner_width = [width - 2, 1].max
              code_width = [self.class::DROPDOWN_CODE_WIDTH, inner_width - 2].min
              {
                code_width: code_width,
                text_width: [inner_width - code_width - 2, 1].max,
              }
            end

            def dropdown_code(code, width, placeholder:)
              value = placeholder ? '--' : code.to_s.upcase
              Shoko::Shared::Terminal::TextMetrics.truncate_to(value, width).ljust(width)
            end

            def dropdown_palette(selected:, placeholder:, kind:)
              return placeholder_dropdown_palette if placeholder
              return selected_dropdown_palette if selected

              {
                row_bg: dropdown_bg,
                code_fg: panel_accent(kind),
                text_fg: dropdown_fg,
                scrollbar_fg: dropdown_muted_fg,
              }
            end

            def placeholder_dropdown_palette
              {
                row_bg: dropdown_bg,
                code_fg: dropdown_muted_fg,
                text_fg: dropdown_muted_fg,
                scrollbar_fg: dropdown_muted_fg,
              }
            end

            def selected_dropdown_palette
              {
                row_bg: dropdown_selected_bg,
                code_fg: dropdown_selected_fg,
                text_fg: dropdown_selected_fg,
                scrollbar_fg: dropdown_selected_fg,
              }
            end

            def dropdown_scrollbar(window, kind)
              total = language_options(kind).length
              visible = [Array(window[:items]).length, 1].max
              return nil if total <= visible

              max_start = [total - visible, 0].max
              thumb_height = dropdown_scrollbar_thumb_height(total, visible)
              thumb_row = dropdown_scrollbar_thumb_row(
                start: window[:start],
                max_start: max_start,
                visible: visible,
                thumb_height: thumb_height
              )
              { thumb_row: thumb_row, thumb_height: thumb_height, visible: visible }
            end

            def dropdown_scrollbar_cell(scrollbar, offset)
              return ' ' unless scrollbar

              thumb_end = scrollbar[:thumb_row] + scrollbar[:thumb_height] - 1
              offset.between?(scrollbar[:thumb_row], thumb_end) ? '█' : '│'
            end

            def dropdown_scrollbar_thumb_height(total, visible)
              (visible.to_f * visible / total).round.clamp(1, visible)
            end

            def dropdown_scrollbar_thumb_row(start:, max_start:, visible:, thumb_height:)
              return 0 if max_start.zero? || visible <= thumb_height

              ((start.to_f / max_start) * (visible - thumb_height)).round
            end

            def visible_length(text)
              Shoko::Shared::Terminal::TextMetrics.visible_length(text.to_s)
            end
          end
        end
      end
    end
  end
end
