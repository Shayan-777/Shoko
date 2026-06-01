# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../menu_design/frame_renderer'
require_relative '../menu_design/status_renderer'
require_relative '../ui/box_drawer'
require_relative '../ui/text_utils'
require_relative 'translator_screen_component/palette_support'
require_relative 'translator_screen_component/interaction_support'
require_relative '../../../../shared/terminal/text_metrics'
require_relative '../../../../shared/hash_normalizer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Menu-mode translator screen with color-distinct source/target panes.
          class TranslatorScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::BoxDrawer
            include Ui::TextUtils
            include TranslatorScreenComponentPaletteSupport
            include TranslatorScreenComponentInteractionSupport

            MAX_DROPDOWN_ROWS = 5
            DROPDOWN_CODE_WIDTH = 4

            def initialize(dependencies: nil, menu_visual_profile: nil)
              super()
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
            end

            def do_render(surface, bounds)
              layout = layout_metrics(bounds)
              render_frame(surface, bounds)
              render_status(surface, bounds, layout)
              render_panel(surface, bounds, layout[:left_box], kind: :source)
              render_panel(surface, bounds, layout[:right_box], kind: :target)
              render_context_menu(surface, bounds)
            end

            def hit_test(column, row, bounds)
              layout = layout_metrics(bounds)
              source_hit = dropdown_hit(layout[:left_box], column, row, :source)
              return source_hit if source_hit

              target_hit = dropdown_hit(layout[:right_box], column, row, :target)
              return target_hit if target_hit
              return { type: :toggle_dropdown, kind: :source } if within_header?(layout[:left_box], column, row)
              return { type: :toggle_dropdown, kind: :target } if within_header?(layout[:right_box], column, row)
              return { type: :focus, focus: :input } if within_body?(layout[:left_box], column, row, :source)

              nil
            end


            # Body rendering helpers for the translator screen.
            BodyClusterLayout = Data.define(:text, :start_index, :end_index, :column_start, :column_end)
            BodyLineLayout = Data.define(:text, :start_index, :end_index, :clusters)
            private

            def render_frame(surface, bounds)
              frame = MenuDesign::FrameRenderer.new(surface, bounds)
              frame.render_title(title: 'Translator', hint: 'TAB focus  ENTER act  S swap  ESC back')
              frame.render_divider
              frame.render_footer(text: footer_text)
            end

            def render_status(surface, bounds, layout)
              MenuDesign::StatusRenderer.new(surface, bounds).render_status(
                row: layout[:status_row],
                indent: layout[:indent],
                left: status_message,
                right: detected_language_label,
                width: layout[:content_width],
                left_color: status_left_color,
                right_color: detected_language_label.empty? ? nil : panel_accent(:source)
              )
            end

            def render_panel(surface, bounds, box, kind:)
              draw_box(surface, bounds, box, border_color: panel_border_color(kind))
              render_panel_title(surface, bounds, box, kind)
              render_dropdown_trigger(surface, bounds, box, kind)
              render_panel_divider(surface, bounds, box, kind) unless dropdown_open_for?(kind)
              render_body(surface, bounds, box, kind)
              render_dropdown(surface, bounds, box, kind) if dropdown_open_for?(kind)
            end

            def render_panel_title(surface, bounds, box, kind)
              surface.write(
                bounds,
                box.row + 1,
                box.col + 2,
                panel_title_badge(kind)
              )
            end

            def render_panel_divider(surface, bounds, box, kind)
              line = '─' * [box.width - 4, 0].max
              surface.write(bounds, box.row + 3, box.col + 2, "#{panel_accent(kind)}#{DIM}#{line}#{reset}")
            end

            def render_body(surface, bounds, box, kind)
              body_lines(box, kind).each_with_index do |line, index|
                surface.write(bounds, body_start_row(box, kind) + index, box.col + 2, line)
              end
            end

            def render_context_menu(surface, bounds)
              popup_box = context_menu_popup_box(bounds)
              return unless popup_box

              draw_box(surface, bounds, popup_box, border_color: context_menu_border_color)
              inner_width = [popup_box.width - 2, 1].max
              context_menu_actions.each_with_index do |action, index|
                render_context_menu_row(
                  surface,
                  bounds,
                  context_menu_row_payload(popup_box, action, index, inner_width)
                )
              end
            end

            def render_context_menu_row(surface, bounds, payload)
              surface.write(bounds, payload[:row], payload[:col], payload[:text])
            end

            def context_menu_row_payload(popup_box, action, index, inner_width)
              label = Shoko::Shared::Terminal::TextMetrics.pad_right(" #{action[:label]}", inner_width)
              {
                row: popup_box.row + 1 + index,
                col: popup_box.col + 1,
                text: "#{context_menu_row_style(action)}#{label}#{reset}",
              }
            end

            def context_menu_row_style(action)
              return "#{context_menu_bg}#{context_menu_fg}" if context_menu_action_enabled?(action[:id])

              "#{context_menu_bg}#{context_menu_disabled_fg}"
            end

            def dropdown_hit(box, column, row, kind)
              return nil unless dropdown_open_for?(kind)
              return nil unless within_dropdown?(box, column, row, kind)

              popup_box = dropdown_popup_box(box, kind)
              index = dropdown_window(kind)[:start] + row - dropdown_item_start_row(popup_box)
              item = language_options(kind)[index]
              return nil unless item

              { type: :select_language, kind: kind, code: item[:code], index: index }
            end

            def panel_active?(kind)
              return true if kind == :source && show_input_cursor?

              translator_focus == kind || dropdown_open_for?(kind)
            end

            def dropdown_open_for?(kind)
              current_mode == (kind == :source ? :translator_source_dropdown : :translator_target_dropdown)
            end

            def pad_body_line(text, width)
              Shoko::Shared::Terminal::TextMetrics.pad_right(text.to_s, width)
            end

            def empty_body_line(width)
              ' ' * width
            end

            def panel_title(kind)
              kind == :source ? 'SOURCE' : 'RESULT'
            end

            def panel_title_badge(kind)
              "#{dropdown_bg}#{panel_accent(kind)}#{BOLD} #{panel_title(kind)} #{reset}"
            end

            # Dropdown rendering helpers for the translator screen.
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

            # Layout and hit-test helpers for the translator screen.
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

            # Session-state access helpers for the translator screen.
            def current_mode
              (menu_state_reader&.mode || :translator).to_sym
            end

            def translator_focus
              (menu_state_reader&.translator_focus || :input).to_sym
            end

            def translator_status
              (menu_state_reader&.translator_status || :idle).to_sym
            end

            def translator_input_text
              menu_state_reader&.translator_input_text.to_s
            end

            def translator_input_cursor
              (menu_state_reader&.translator_input_cursor || translator_input_text.length).to_i
            end

            def translator_output_text
              menu_state_reader&.translator_output_text.to_s
            end

            def translator_message
              menu_state_reader&.translator_message.to_s
            end

            def translator_selection
              normalize_hash(menu_state_reader&.translator_selection)
            end

            def translator_context_menu
              normalize_hash(menu_state_reader&.translator_context_menu)
            end

            def detected_language_label
              detected = menu_state_reader&.translator_detected_source_lang.to_s
              detected.empty? ? '' : "Detected: #{language_name(detected)}"
            end

            def dropdown_selected
              (menu_state_reader&.translator_dropdown_selected || 0).to_i
            end

            def selected_language_code(kind)
              field = kind == :source ? :translator_source_lang : :translator_target_lang
              menu_state_reader&.public_send(field).to_s
            end

            def language_name(code)
              return 'Auto Detect' if code.to_s == 'auto'

              language_options(:target).find { |item| item[:code] == code.to_s }.to_h[:name] || code.to_s
            end

            def language_options(kind)
              languages = Array(menu_state_reader&.translator_languages).map { |item| normalize_language(item) }
              kind == :source ? [{ code: 'auto', name: 'Auto Detect' }, *languages] : languages
            end

            def normalize_language(item)
              normalized = Shoko::Shared::HashNormalizer.symbolize_keys(item) || {}
              {
                code: normalized[:code].to_s,
                name: normalized[:name].to_s,
              }
            end

            def normalize_hash(value)
              return nil unless value.is_a?(Hash)

              Shoko::Shared::HashNormalizer.symbolize_keys(value)
            end

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
            end

            def body_lines(box, kind)
              height = body_height(box, kind)
              width = body_width(box)
              if body_text(kind).empty?
                return empty_source_lines(width, height) if kind == :source && show_input_cursor?

                return placeholder_lines(kind, width, height)
              end

              visible_layouts = visible_body_layouts_for_render(kind, width).first(height)
              rendered = visible_layouts.map { |line| render_body_layout_line(line, kind, width) }
              padded_lines(rendered, width, height)
            end

            def body_layouts(kind, width)
              build_text_layout(body_text(kind), width)
            end

            def body_text(kind)
              kind == :source ? translator_input_text : translator_output_text
            end

            def empty_source_lines(width, height)
              padded_lines([cursor_placeholder_line(width)].first(height), width, height)
            end

            def placeholder_lines(kind, width, height)
              text = kind == :source ? 'Type or paste text here.' : output_placeholder
              lines = [style_placeholder_line(text, width)]
              lines + Array.new([height - lines.length, 0].max) { empty_body_line(width) }
            end

            def output_placeholder
              translator_status == :error ? status_message : 'Translation appears here.'
            end

            def padded_lines(lines, width, height)
              padded = Array(lines).map { |line| pad_body_line(line, width) }
              padded + Array.new([height - padded.length, 0].max) { empty_body_line(width) }
            end

            def footer_text
              'Drag to select text. Right-click for Copy to Clipboard or Paste from Clipboard.'
            end

            def status_message
              return translator_message unless translator_message.empty?

              translator_status == :error ? 'Translation failed.' : 'Choose languages, then type on the left.'
            end

            def show_input_cursor?
              current_mode == :translator && translator_focus == :input
            end

            def cursor_placeholder_line(width)
              prompt_width = [width - 1, 1].max
              prompt = Shoko::Shared::Terminal::TextMetrics.truncate_to('Type or paste text here.', prompt_width)
              cursor = "#{cursor_bg}#{cursor_fg} #{reset}#{panel_muted_fg}"
              "#{cursor}#{prompt}#{reset}"
            end

            def style_placeholder_line(text, width)
              content = Shoko::Shared::Terminal::TextMetrics.truncate_to(text.to_s, width)
              "#{panel_muted_fg}#{content}#{reset}"
            end

            def render_body_layout_line(line, kind, width)
              selection = selection_for_kind(kind)
              cursor_index = source_cursor_index_for(kind, selection)
              return style_empty_body_line(cursor_index) if line.clusters.empty?

              rendered = line.clusters.each_with_object(+'') do |cluster, buffer|
                buffer << styled_cluster_text(cluster, selection, cursor_index)
              end
              if cursor_index && cursor_index == line.end_index && line.clusters.last.column_end < width
                rendered << styled_cursor_cell
              end
              rendered
            end

            def style_empty_body_line(cursor_index)
              return '' unless cursor_index

              styled_cursor_cell
            end

            def styled_cluster_text(cluster, selection, cursor_index)
              style = if cursor_index && cursor_covers_cluster?(cursor_index, cluster)
                        "#{cursor_bg}#{cursor_fg}"
                      elsif selection && cluster_selected?(cluster, selection)
                        "#{selection_bg}#{selection_fg}"
                      else
                        panel_text_fg
                      end
              "#{style}#{cluster.text}#{reset}"
            end

            def styled_cursor_cell
              "#{cursor_bg}#{cursor_fg} #{reset}"
            end

            def selection_for_kind(kind)
              selection = translator_selection
              return nil unless selection && selection[:pane].to_sym == kind

              start_index, end_index = selection_bounds(selection)
              return nil unless end_index > start_index

              {
                start_index: start_index,
                end_index: end_index,
              }
            end

            def selection_bounds(selection)
              start_index = selection[:start_index].to_i
              end_index = selection[:end_index].to_i
              start_index <= end_index ? [start_index, end_index] : [end_index, start_index]
            end

            def source_cursor_index_for(kind, selection)
              return nil unless kind == :source && show_input_cursor?
              return nil if selection

              translator_input_cursor.clamp(0, translator_input_text.length)
            end

            def cursor_covers_cluster?(cursor_index, cluster)
              cursor_index >= cluster.start_index && cursor_index < cluster.end_index
            end

            def cluster_selected?(cluster, selection)
              cluster.start_index < selection[:end_index] && cluster.end_index > selection[:start_index]
            end

            def build_text_layout(text, width)
              state = text_layout_state(width)
              text.to_s.each_grapheme_cluster do |cluster|
                process_text_layout_cluster(state, cluster)
              end
              finalize_text_layout(state)
            end

            def visible_body_layouts_for_render(kind, width)
              layouts = body_layouts(kind, width).dup
              return layouts unless needs_cursor_overflow_line?(kind, layouts, width)

              cursor_index = translator_input_cursor.clamp(0, translator_input_text.length)
              layouts << build_line_layout('', cursor_index, cursor_index, [])
            end

            def build_line_layout(text, start_index, end_index, clusters)
              BodyLineLayout.new(
                text: text.dup,
                start_index: start_index,
                end_index: end_index,
                clusters: clusters.dup
              )
            end

            def text_layout_state(width)
              {
                visible_width: [width.to_i, 1].max,
                codepoint_index: 0,
                line_start_index: 0,
                line_width: 0,
                line_text: +'',
                line_clusters: [],
                lines: [],
              }
            end

            def process_text_layout_cluster(state, cluster)
              return process_newline_cluster(state, cluster) if cluster == "\n"

              cluster_width = cluster_display_width(cluster)
              wrap_text_layout_line(state) if needs_text_layout_wrap?(state, cluster_width)
              append_text_layout_cluster(state, cluster, cluster_width)
            end

            def process_newline_cluster(state, cluster)
              push_text_layout_line(state)
              state[:codepoint_index] += cluster.length
              reset_text_layout_line(state)
            end

            def needs_text_layout_wrap?(state, cluster_width)
              state[:line_clusters].any? && state[:line_width] + cluster_width > state[:visible_width]
            end

            def wrap_text_layout_line(state)
              push_text_layout_line(state)
              reset_text_layout_line(state)
            end

            def append_text_layout_cluster(state, cluster, cluster_width)
              cluster_start = state[:codepoint_index]
              state[:codepoint_index] += cluster.length
              state[:line_clusters] << BodyClusterLayout.new(
                text: cluster,
                start_index: cluster_start,
                end_index: state[:codepoint_index],
                column_start: state[:line_width],
                column_end: state[:line_width] + cluster_width
              )
              state[:line_width] += cluster_width
              state[:line_text] << cluster
            end

            def finalize_text_layout(state)
              push_text_layout_line(state)
              state[:lines]
            end

            def push_text_layout_line(state)
              state[:lines] << build_line_layout(
                state[:line_text],
                state[:line_start_index],
                state[:codepoint_index],
                state[:line_clusters]
              )
            end

            def reset_text_layout_line(state)
              state[:line_start_index] = state[:codepoint_index]
              state[:line_width] = 0
              state[:line_text] = +''
              state[:line_clusters] = []
            end

            def cluster_display_width(cluster)
              [Shoko::Shared::Terminal::TextMetrics.display_width_for(cluster), 1].max
            end

            def needs_cursor_overflow_line?(kind, layouts, width)
              return false unless kind == :source && show_input_cursor? && selection_for_kind(:source).nil?

              cursor_index = translator_input_cursor.clamp(0, translator_input_text.length)
              last_line = layouts.last || build_line_layout('', 0, 0, [])
              cursor_index == last_line.end_index && last_line.clusters.last&.column_end.to_i >= width
            end
          end
        end
      end
    end
  end
end
