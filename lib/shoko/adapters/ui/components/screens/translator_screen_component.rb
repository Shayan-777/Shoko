# frozen_string_literal: true

require 'shoko/shared/index_range'
require 'shoko/core/models/translation_language'
require_relative '../base_component'
require_relative '../menu_design/canvas_frame'
require_relative '../menu_design/view_accents'
require_relative '../status_bar/palette'
require_relative '../ui/box_drawer'
require_relative '../ui/list_windowing'
require_relative '../ui/text_utils'
require_relative '../ui/cursor_blink'
require 'shoko/shared/terminal/text_metrics'
require 'shoko/shared/hash_normalizer'
require 'shoko/shared/terminal/ansi'
require 'shoko/shared/language_directory'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Menu-mode translator — the emerald member, mirroring the in-book
          # translator's surfaces on the canvas: the source pane is the raised
          # compose well, the result pane the translation card, both separated
          # from the canvas purely by elevation. Language pickers drop down as
          # recessed candidate lists with the family's selection treatment;
          # text selection, the clipboard context menu, and the blinking
          # thin-stripe caret all carry over unchanged.
          class TranslatorScreenComponent < BaseComponent
            include Ui::TextUtils
            include Ui::CursorBlink

            Palette = StatusBar::Palette
            BOLD = Shoko::Shared::Terminal::Ansi::BOLD

            MAX_DROPDOWN_ROWS = 5
            DROPDOWN_CODE_WIDTH = 4
            DEFAULT_SOURCE_BODY_WIDTH = 40

            def initialize(menu_state_reader: nil, menu_session_mutator: nil, menu_hit_registry: nil,
                           menu_visual_profile: nil)
              super()
              @menu_state_reader = menu_state_reader
              @menu_session_mutator = menu_session_mutator
              @menu_hit_registry = menu_hit_registry
              @menu_visual_profile = menu_visual_profile
              initialize_cursor_blink
            end

            def do_render(surface, bounds)
              layout = layout_metrics(bounds)
              frame = MenuDesign::CanvasFrame.new(surface, bounds)
              frame.paint
              frame.render_rule(title: 'Translator', accent: view_accent, meta: detected_language_label.downcase)
              render_status(frame, layout)
              render_panel(surface, bounds, layout[:left_box], kind: :source)
              render_panel(surface, bounds, layout[:right_box], kind: :target)
              render_context_menu(surface, bounds)
              frame.render_hint(translator_hint)
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

            CONTEXT_MENU_ACTIONS = [
              { id: :copy_to_clipboard, label: 'Copy to Clipboard' },
              { id: :paste_from_clipboard, label: 'Paste from Clipboard' },
            ].freeze

            def body_hit(column, row, bounds)
              layout = layout_metrics(bounds)

              source_hit = body_hit_for_box(layout[:left_box], column, row, :source)
              return source_hit if source_hit

              body_hit_for_box(layout[:right_box], column, row, :target)
            end

            def selection_from_points(start_column:, start_row:, end_column:, end_row:, bounds:)
              start_hit = body_hit(start_column, start_row, bounds)
              end_hit = body_hit(end_column, end_row, bounds)
              return nil unless start_hit && end_hit
              return nil unless start_hit[:kind] == end_hit[:kind]

              start_index, end_index = [start_hit[:index], end_hit[:index]].minmax
              return nil if start_index == end_index

              {
                pane: start_hit[:kind],
                start_index: start_index,
                end_index: end_index,
              }
            end

            def selection_text(selection = translator_selection)
              return '' unless selection

              kind = selection[:pane].to_sym
              start_index, end_index = Shoko::Shared::IndexRange.ordered(selection)
              return '' if end_index <= start_index

              body_text(kind)[start_index...end_index].to_s
            end

            def selection_contains_hit?(selection, hit)
              return false unless selection && hit
              return false unless selection[:pane].to_sym == hit[:kind].to_sym

              start_index, end_index = Shoko::Shared::IndexRange.ordered(selection)
              return false if end_index <= start_index

              if hit[:inside_cluster]
                hit[:cluster_start_index] < end_index && hit[:cluster_end_index] > start_index
              else
                hit[:index] > start_index && hit[:index] < end_index
              end
            end

            def context_menu_hit(column, row, bounds)
              popup_box = context_menu_popup_box(bounds)
              return nil unless popup_box
              return nil unless within_context_menu?(popup_box, column, row)

              action = context_menu_action_at(popup_box, row)
              return nil unless context_menu_action_enabled?(action[:id])

              action
            end

            def context_menu_popup_box(bounds)
              menu = translator_context_menu
              return nil unless menu

              width = context_menu_width
              height = context_menu_actions.length + 2
              col = menu[:anchor_column].to_i.clamp(1, [bounds.width - width + 1, 1].max)
              row = adjusted_context_menu_row(menu[:anchor_row].to_i, height, bounds.height)
              Ui::BoxDrawer::BoxSpec.new(row: row, col: col, width: width, height: height)
            end

            def context_menu_actions
              CONTEXT_MENU_ACTIONS
            end

            # --- Cursor movement (parity with the note editor) ---
            # Left/right step by one character; up/down move across the visual (wrapped) lines the
            # source pane actually renders, preserving the column. The new cursor is persisted to
            # translator_input_cursor, the same field the renderer reads.
            def handle_move_left
              write_cursor([source_cursor - 1, 0].max)
            end

            def handle_move_right
              write_cursor([source_cursor + 1, translator_input_text.length].min)
            end

            def handle_move_up
              return scroll_output(-1) if translator_focus == :target

              move_cursor_by_visual_line(-1)
            end

            def handle_move_down
              return scroll_output(1) if translator_focus == :target

              move_cursor_by_visual_line(1)
            end

            private

            def render_status(frame, layout)
              frame.render_status(
                row: layout[:status_row],
                left: status_message,
                left_fg: status_left_color
              )
            end

            # The pane is a surface, not a box: the source pane sits on the
            # raised compose-well tone, the result pane on the translation
            # card tone — elevation is the whole frame.
            def render_panel(surface, bounds, box, kind:)
              fill_pane(surface, bounds, box, kind)
              render_panel_title(surface, bounds, box, kind)
              render_dropdown_trigger(surface, bounds, box, kind)
              render_body(surface, bounds, box, kind)
              render_dropdown(surface, bounds, box, kind) if dropdown_open_for?(kind)
            end

            def fill_pane(surface, bounds, box, kind)
              blank = "#{Palette::RESET}#{panel_bg(kind)}#{' ' * box.width}#{Palette::RESET}"
              box.height.times { |offset| surface.write(bounds, box.row + offset, box.col, blank) }
            end

            def render_panel_title(surface, bounds, box, kind)
              surface.write(
                bounds,
                box.row + 1,
                box.col + 2,
                panel_title_badge(kind)
              )
            end

            def render_body(surface, bounds, box, kind)
              # Cache the source pane's text width so cursor up/down can navigate the same
              # visual (wrapped) lines that were last rendered — mirrors the note editor's
              # @editor_text_width. Movement happens off-frame, where bounds are unavailable.
              @source_body_width = body_width(box) if kind == :source
              if kind == :target
                @target_body_width = body_width(box)
                @target_body_height = body_height(box, kind)
              end
              base = "#{Palette::RESET}#{panel_bg(kind)}#{panel_text_fg(kind)}"
              body_lines(box, kind).each_with_index do |line, index|
                surface.write(bounds, body_start_row(box, kind) + index, box.col + 2,
                              "#{base}#{line}#{Palette::RESET}")
              end
            end

            def render_context_menu(surface, bounds)
              popup_box = context_menu_popup_box(bounds)
              return unless popup_box

              fill_dropdown(surface, bounds, popup_box)
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

            # A small label on the pane's first row; the active pane's label
            # takes the emerald signature, the other rests dim.
            def panel_title_badge(kind)
              label_fg = panel_active?(kind) ? "#{BOLD}#{view_accent}" : Palette::TRANS_DIM_FG
              "#{Palette::RESET}#{panel_bg(kind)}#{label_fg}#{panel_title(kind)}#{Palette::RESET}"
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
              fill_dropdown(surface, bounds, popup_box)
              render_dropdown_filter(surface, bounds, popup_box)
              register_dropdown_wheel(bounds, popup_box)
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

            def render_dropdown_filter(surface, bounds, popup_box)
              width = dropdown_inner_width(popup_box)
              query = menu_state_reader&.translator_dropdown_query.to_s
              label = query.empty? ? 'type to filter · Tab side' : "filter: #{query}▏"
              text = Shoko::Shared::Terminal::TextMetrics.truncate_to(label, width)
              padding = ' ' * [width - visible_length(text), 0].max
              surface.write(
                bounds, popup_box.row, popup_box.col + 1,
                "#{Palette::RESET}#{dropdown_bg}#{dropdown_muted_fg}#{text}#{padding}#{Palette::RESET}"
              )
            end

            # One region over the open picker, so wheel turns anywhere on it
            # move the language selection like every other list.
            def register_dropdown_wheel(bounds, popup_box)
              menu_hits&.register(
                col: bounds.x + popup_box.col - 1, row: bounds.y + popup_box.row - 1,
                width: popup_box.width, height: popup_box.height,
                action: { type: :list_wheel, list: :translator_language }
              )
            end

            def menu_hits
              @menu_hit_registry
            end

            # The picker recesses below the pane on the darkest family tone,
            # so it reads as a layer without needing a border.
            def fill_dropdown(surface, bounds, popup_box)
              blank = "#{Palette::RESET}#{dropdown_bg}#{' ' * popup_box.width}#{Palette::RESET}"
              popup_box.height.times { |offset| surface.write(bounds, popup_box.row + offset, popup_box.col, blank) }
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

            # The window scrolls only when the selection leaves it (the
            # family's ensure-visible rule) instead of re-centering — rows
            # stay put under the pointer, so click-to-select then
            # click-to-apply lands on the same candidate.
            def dropdown_window(kind)
              items = language_options(kind)
              visible = self.class::MAX_DROPDOWN_ROWS
              @dropdown_scroll = Ui::ListWindowing.scroll_to_reveal(
                dropdown_selected, scroll: @dropdown_scroll || 0, visible: visible, total: items.length
              )
              { start: @dropdown_scroll, items: items.slice(@dropdown_scroll, visible) || [] }
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
              row = dropdown_item_start_row(context[:popup_box]) + offset
              context[:surface].write(
                context[:bounds], row, context[:popup_box].col + 1,
                dropdown_row(
                  code: item[:code], name: item[:name], width: context[:width],
                  selected: item[:index] == dropdown_selected, kind: kind,
                  placeholder: item[:placeholder] == true,
                  hovered: dropdown_row_hovered?(context, row),
                  scrollbar_cell: dropdown_scrollbar_cell(context[:scrollbar], offset)
                )
              )
            end

            # The pointer-hovered candidate takes the family hover tone, like
            # every other list row.
            def dropdown_row_hovered?(context, row)
              hits = menu_hits
              return false unless hits

              bounds = context[:bounds]
              popup_box = context[:popup_box]
              hits.hover?(
                col: bounds.x + popup_box.col - 1, row: bounds.y + row - 1,
                width: popup_box.width, height: 1
              )
            end

            def dropdown_row(code:, name:, width:, selected:, kind:, placeholder: false, hovered: false,
                             scrollbar_cell: ' ')
              layout = dropdown_row_layout(width)
              palette = dropdown_palette(selected: selected, placeholder: placeholder, hovered: hovered, kind: kind)
              code_text = dropdown_code(code, layout[:code_width], placeholder: placeholder)
              text = Shoko::Shared::Terminal::TextMetrics.truncate_to(name.to_s, layout[:text_width])
              padding = ' ' * [layout[:text_width] - visible_length(text), 0].max

              "#{Palette::RESET}#{palette[:row_bg]} " \
                "#{palette[:code_fg]}#{code_text} " \
                "#{palette[:text_fg]}#{text}#{padding}" \
                "#{scrollbar_cell} " \
                "#{Palette::RESET}"
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

            def dropdown_palette(selected:, placeholder:, kind:, hovered: false)
              return placeholder_dropdown_palette if placeholder
              return selected_dropdown_palette if selected

              _ = kind
              {
                row_bg: hovered ? Palette::TRANS_HOVER_BG : dropdown_bg,
                code_fg: Palette::TRANS_CODE_FG,
                text_fg: dropdown_fg,
              }
            end

            def placeholder_dropdown_palette
              {
                row_bg: dropdown_bg,
                code_fg: dropdown_muted_fg,
                text_fg: dropdown_muted_fg,
              }
            end

            def selected_dropdown_palette
              {
                row_bg: dropdown_selected_bg,
                code_fg: dropdown_selected_fg,
                text_fg: dropdown_selected_fg,
              }
            end

            def dropdown_scrollbar(window, kind)
              total = language_options(kind).length
              visible = [Array(window[:items]).length, 1].max
              return nil if total <= visible

              Ui::ListWindowing.scrollbar_thumb(total: total, visible: visible, scroll: window[:start])
            end

            # The family scrollbar: a full-height █ track in the lighter tone
            # with a brand-accent █ thumb, riding the row so selection and
            # hover strips pass underneath it — no line glyphs.
            def dropdown_scrollbar_cell(scrollbar, offset)
              return ' ' unless scrollbar

              thumb_end = scrollbar[:start] + scrollbar[:size] - 1
              color = if offset.between?(scrollbar[:start], thumb_end)
                        Palette::TRANS_SCROLL_THUMB_FG
                      else
                        Palette::TRANS_SCROLL_TRACK_FG
                      end
              "#{color}█"
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
              languages = Array(menu_state_reader&.translator_languages).map { |item| Shoko::Core::Models::TranslationLanguage.normalized_entry(item) }
              Shoko::Shared::LanguageDirectory.candidates_for(
                languages,
                side: kind,
                source_code: selected_language_code(:source),
                query: menu_state_reader&.translator_dropdown_query.to_s
              )
            end

            def normalize_hash(value)
              return nil unless value.is_a?(Hash)

              Shoko::Shared::HashNormalizer.symbolize_keys(value)
            end

            attr_reader :menu_state_reader, :menu_session_mutator

            def source_cursor
              translator_input_cursor.clamp(0, translator_input_text.length)
            end

            def source_body_width
              @source_body_width || DEFAULT_SOURCE_BODY_WIDTH
            end

            def write_cursor(cursor)
              menu_session_mutator&.update_menu(translator_input_cursor: cursor)
              record_cursor_activity
            end

            def move_cursor_by_visual_line(delta)
              text = translator_input_text
              layouts = build_text_layout(text, source_body_width)
              line_index, column = visual_cursor_line_and_column(layouts, source_cursor)
              target_line = layouts[(line_index + delta).clamp(0, layouts.length - 1)]
              new_cursor, = index_for_line_column(target_line, column)
              write_cursor(new_cursor.clamp(0, text.length))
            end

            # Locate the cursor's visual line and display column within the rendered (wrapped) layout,
            # matching how render_body_layout_line draws it: inside the cluster that contains the index,
            # else at the end of the line — but a wrapped continuation owns a shared boundary index.
            def visual_cursor_line_and_column(layouts, cursor)
              layouts.each_with_index do |line, index|
                line.clusters.each do |cluster|
                  return [index, cluster.column_start] if cursor >= cluster.start_index && cursor < cluster.end_index
                end
                next unless cursor == line.end_index

                next_line = layouts[index + 1]
                next if next_line && next_line.start_index == cursor

                return [index, line.clusters.last&.column_end || 0]
              end
              [[layouts.length - 1, 0].max, 0]
            end

            def body_lines(box, kind)
              height = body_height(box, kind)
              width = body_width(box)
              if body_text(kind).empty?
                return empty_source_lines(width, height) if kind == :source && show_input_cursor?

                return placeholder_lines(kind, width, height)
              end

              layouts = visible_body_layouts_for_render(kind, width)
              start = body_window_start(kind, layouts, height)
              visible_layouts = layouts.slice(start, height) || []
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

            def status_message
              return translator_message unless translator_message.empty?

              translator_status == :error ? 'Translation failed.' : 'Choose languages, then type on the left.'
            end

            def show_input_cursor?
              current_mode == :translator && translator_focus == :input
            end

            def cursor_placeholder_line(width)
              prompt = Shoko::Shared::Terminal::TextMetrics.truncate_to('Type or paste text here.', width)
              styled = "#{panel_muted_fg}#{prompt}"
              inline_cursor_text(styled, 0, width: width, style_prefix: Palette::TRANS_CARET_FG,
                                            restore_prefix: panel_muted_fg)
            end

            def style_placeholder_line(text, width)
              content = Shoko::Shared::Terminal::TextMetrics.truncate_to(text.to_s, width)
              "#{panel_muted_fg}#{content}"
            end

            def render_body_layout_line(line, kind, width)
              selection = selection_for_kind(kind)
              rendered = line.clusters.each_with_object(+'') do |cluster, buffer|
                buffer << styled_cluster_text(cluster, selection, kind)
              end
              cursor_column = cursor_column_for_line(line, source_cursor_index_for(kind, selection), width)
              return rendered unless cursor_column

              # Thin blinking stripe, identical to the note editor's caret, instead of a block cell.
              inline_cursor_text(rendered, cursor_column, width: width,
                                                          style_prefix: Palette::TRANS_CARET_FG,
                                                          restore_prefix: panel_text_fg(kind))
            end

            # Visual column of the caret on this rendered line, or nil if it is not on it. A full (wrapped)
            # line yields to the next line so the caret never renders twice at a soft-wrap boundary.
            def cursor_column_for_line(line, cursor_index, width)
              return nil unless cursor_index

              line.clusters.each do |cluster|
                return cluster.column_start if cursor_index >= cluster.start_index && cursor_index < cluster.end_index
              end
              return nil unless cursor_index == line.end_index

              last = line.clusters.last
              return nil if last && last.column_end >= width

              last ? last.column_end : 0
            end

            # Selected clusters take the family selection strip; every cluster
            # restores the pane's own surface afterwards, so the background
            # never drops out mid-row.
            def styled_cluster_text(cluster, selection, kind)
              restore = "#{panel_bg(kind)}#{panel_text_fg(kind)}"
              if selection && cluster_selected?(cluster, selection)
                "#{Palette::TRANS_SELECTED_BG}#{Palette::LANDING_TITLE_FG}#{cluster.text}#{restore}"
              else
                "#{restore}#{cluster.text}"
              end
            end

            def selection_for_kind(kind)
              selection = translator_selection
              return nil unless selection && selection[:pane].to_sym == kind

              start_index, end_index = Shoko::Shared::IndexRange.ordered(selection)
              return nil unless end_index > start_index

              {
                start_index: start_index,
                end_index: end_index,
              }
            end

            def source_cursor_index_for(kind, selection)
              return nil unless kind == :source && show_input_cursor?
              return nil if selection

              translator_input_cursor.clamp(0, translator_input_text.length)
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

            def body_window_start(kind, layouts, height)
              max_start = [layouts.length - height, 0].max
              return translator_output_scroll.clamp(0, max_start) if kind == :target

              line, = visual_cursor_line_and_column(layouts, source_cursor)
              [line - height + 1, 0].max.clamp(0, max_start)
            end

            def translator_output_scroll
              (menu_state_reader&.translator_output_scroll || 0).to_i
            end

            def scroll_output(delta)
              width = @target_body_width || source_body_width
              height = @target_body_height || 1
              layouts = body_layouts(:target, width)
              max_scroll = [layouts.length - height, 0].max
              value = (translator_output_scroll + delta.to_i).clamp(0, max_scroll)
              menu_session_mutator&.update_menu(translator_output_scroll: value)
              record_cursor_activity
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

            # Palette: the family's fixed translator tones (theme-independent,
            # like every bar-anchored panel).
            def view_accent
              MenuDesign::ViewAccents.for(:translator)
            end

            def translator_hint
              if %i[translator_source_dropdown translator_target_dropdown].include?(current_mode)
                'TYPE filter · TAB switch side · ENTER select · ESC close'
              else
                'ALT/CTRL+ENTER translate · TAB focus · SHIFT+TAB swap · arrows edit/scroll'
              end
            end

            def status_left_color
              case translator_status
              when :done, :ready then Palette::TRANS_ACCENT_FG
              when :error then Palette::LANDING_QUIT_FG
              when :loading, :working then Palette::LIST_MATCH_FG
              else Palette::LANDING_DIM_FG
              end
            end

            def panel_bg(kind)
              kind == :source ? Palette::TRANS_FIELD_BG : Palette::TRANS_BG
            end

            def panel_text_fg(kind)
              kind == :source ? Palette::TRANS_INPUT_FG : Palette::TRANS_TEXT_FG
            end

            def panel_muted_fg
              Palette::TRANS_PLACEHOLDER_FG
            end

            def context_menu_bg
              dropdown_bg
            end

            def context_menu_fg
              Palette::TRANS_BUTTON_FG
            end

            def context_menu_disabled_fg
              Palette::TRANS_DIM_FG
            end

            def dropdown_bg
              Palette::TRANS_TAB_INACTIVE_BG
            end

            def dropdown_selected_bg
              Palette::TRANS_SELECTED_BG
            end

            def dropdown_fg
              Palette::TRANS_LANG_FG
            end

            def dropdown_selected_fg
              "#{Palette::LANDING_TITLE_FG}#{BOLD}"
            end

            def dropdown_muted_fg
              Palette::TRANS_DIM_FG
            end

            def reset
              Shoko::Shared::Terminal::Ansi::RESET
            end

            def body_hit_for_box(box, column, row, kind)
              return nil unless within_body?(box, column, row, kind)

              width = body_width(box)
              line_index = row - body_start_row(box, kind)
              line = visible_body_line(kind, width, line_index, body_height(box, kind))
              rel_column = (column - (box.col + 2)).clamp(0, width)
              index, cluster = index_for_line_column(line, rel_column)
              {
                kind: kind,
                index: index,
                line_index: line_index,
                cluster_start_index: cluster&.start_index,
                cluster_end_index: cluster&.end_index,
                inside_cluster: !cluster.nil?,
              }
            end

            def visible_body_line(kind, width, line_index, height)
              layouts = visible_body_layouts_for_render(kind, width)
              start = body_window_start(kind, layouts, height)
              return layouts[start + line_index] if layouts[start + line_index]

              layouts.last || build_line_layout('', 0, 0, [])
            end

            def index_for_line_column(line, column)
              line.clusters.each do |cluster|
                return [cluster.start_index, nil] if column < cluster.column_start
                next unless column < cluster.column_end

                midpoint = cluster.column_start + ((cluster.column_end - cluster.column_start) / 2.0)
                index = column < midpoint ? cluster.start_index : cluster.end_index
                return [index, cluster]
              end

              [line.end_index, nil]
            end

            def context_menu_width
              label_width = context_menu_actions.map do |action|
                Shoko::Shared::Terminal::TextMetrics.visible_length(action[:label])
              end.max || 0
              label_width + 4
            end

            def within_context_menu?(popup_box, column, row)
              column.between?(popup_box.col + 1, popup_box.col + popup_box.width - 2) &&
                row.between?(popup_box.row + 1, popup_box.row + context_menu_actions.length)
            end

            def context_menu_action_at(popup_box, row)
              context_menu_actions[row - popup_box.row - 1]
            end

            def adjusted_context_menu_row(anchor_row, popup_height, bounds_height)
              base_row = [anchor_row, 1].max
              max_row = [bounds_height - popup_height + 1, 1].max
              return base_row if base_row <= max_row

              [anchor_row - popup_height + 1, 1].max
            end

            def context_menu_action_enabled?(action_id)
              case action_id
              when :copy_to_clipboard
                translator_copy_available?
              when :paste_from_clipboard
                true
              else
                false
              end
            end

            def translator_copy_available?
              menu = translator_context_menu
              selection = translator_selection
              return false unless menu && selection
              return false unless selection[:pane].to_sym == menu[:pane].to_sym

              !selection_text(selection).empty?
            end
          end
        end
      end
    end
  end
end
