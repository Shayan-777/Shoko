# frozen_string_literal: true

require_relative '../../../shared/type_coercion'

require_relative 'base_component'
require_relative 'ui/overlay_layout'
require_relative 'ui/annotation_markup'
require_relative 'ui/annotation_list_input'
require_relative 'ui/cursor_blink'
require_relative '../../../shared/terminal/text_metrics'
require_relative '../../../shared/terminal/ansi'
require_relative '../../../shared/key_definitions'
require_relative '../../../shared/terminal/text_sanitizer'

module Shoko
  module Adapters
    module Ui
      module Components
        # Overlay for creating/editing annotations.
        # Styled to match the tooltip popup glass design.
        class AnnotationEditorOverlayComponent < BaseComponent
          include Adapters::Ui::Constants::Ui
          include Ui::CursorBlink

          SAVE_KEYS = ["\x13"].freeze # Ctrl+S
          BACKSPACE_KEYS = ["\x08", "\x7F", "\b"].freeze
          SPELL_SUGGESTION_LIMIT = 5
          SPELL_POPUP_MIN_WIDTH = 18
          SPELL_POPUP_MAX_WIDTH = 34
          SPELL_POPUP_KIND_WIDTH = 3
          WORD_CHARACTER = /\A[\p{L}\p{M}\p{N}'’-]\z/.freeze
          WORD_CONTENT = /[\p{L}\p{N}]/.freeze

          # Style codes
          BOLD = "\e[1m"
          DIM = "\e[2m"
          ITALIC = "\e[3m"
          RESET_STYLE = "\e[22;23;24m"
          PANEL_BG_LIGHT = "\e[48;2;233;236;241m"
          QUOTE_BG_LIGHT = "\e[48;2;220;226;234m"
          PANEL_FG_LIGHT = "\e[38;2;32;38;48m"
          PANEL_FG_EMPHASIS_LIGHT = "\e[38;2;22;56;84m"
          GLASS_FG_LIGHT = "\e[38;2;116;126;141m#{Shoko::Shared::Terminal::Ansi::DIM}".freeze
          SPELL_MENU_BG_LIGHT = "\e[48;2;231;236;243m"
          SPELL_MENU_BG_DARK = "\e[48;2;31;35;53m"
          SPELL_MENU_SELECTED_BG_LIGHT = "\e[48;2;210;220;236m"
          SPELL_MENU_SELECTED_BG_DARK = "\e[48;2;67;74;108m"
          SPELL_MENU_FG_LIGHT = "\e[38;2;43;50;63m"
          SPELL_MENU_FG_DARK = "\e[38;2;211;220;246m"
          SPELL_MENU_SELECTED_FG_LIGHT = "\e[38;2;22;40;57m#{BOLD}"
          SPELL_MENU_SELECTED_FG_DARK = "\e[38;2;242;246;255m#{BOLD}"
          SPELL_MENU_KIND_FG_LIGHT = "\e[38;2;22;102;136m"
          SPELL_MENU_KIND_FG_DARK = "\e[38;2;138;180;255m"
          SPELL_MENU_MUTED_FG_LIGHT = "\e[38;2;122;131;149m"
          SPELL_MENU_MUTED_FG_DARK = "\e[38;2;125;132;162m"
          BACKDROP_FG_DARK = "\e[38;2;34;38;50m#{Shoko::Shared::Terminal::Ansi::DIM}".freeze
          BACKDROP_FG_LIGHT = "\e[38;2;224;228;234m#{Shoko::Shared::Terminal::Ansi::DIM}".freeze

          PADDING_H = 2
          PADDING_V = 1

          attr_reader :visible, :selected_text, :note, :chapter_index, :annotation_id

          def initialize(selected_text:, range:, chapter_index:, annotation: nil, color_mode: :dark,
                         rendered_lines: nil)
            super()
            @selected_text = (selected_text || '').dup
            @range = range
            @chapter_index = chapter_index
            @color_mode = color_mode
            @rendered_lines = rendered_lines.is_a?(Hash) ? rendered_lines : {}
            @backdrop_rows_key = nil
            @backdrop_rows = {}
            @annotation_id = annotation.is_a?(Hash) ? (annotation[:id] || annotation['id']) : nil
            note_source = annotation.is_a?(Hash) ? (annotation[:note] || annotation['note']) : nil
            @note = (note_source || '').dup
            @cursor_pos = @note.length
            @visible = true
            @button_regions = {}
            @note_inner_width = nil
            @spell_suggestions = nil
            initialize_cursor_blink
            @overlay_sizing = Ui::OverlaySizing.new(
              width_ratio: 0.55,
              width_padding: 10,
              min_width: 46,
              height_ratio: 0.50,
              height_padding: 8,
              min_height: 12
            )
          end

          def visible?
            @visible
          end

          def hide
            dismiss_spell_suggestions
            @visible = false
          end

          def update_color_mode(mode)
            @color_mode = mode.to_s == 'light' ? :light : :dark
          end

          def update_rendered_lines(rendered_lines)
            @rendered_lines = rendered_lines.is_a?(Hash) ? rendered_lines : {}
            @backdrop_rows_key = nil
            @backdrop_rows = {}
          end

          def selection_range
            @range
          end

          def render(surface, bounds)
            do_render(surface, bounds)
          end

          def do_render(surface, bounds)
            return unless @visible

            layout = overlay_layout(bounds)
            context = editor_render_context(surface, bounds, layout)
            fill_editor_background(context)
            current_row = render_header(context, context[:start_row])
            current_row = render_quote(context, current_row)
            note_end_row = layout.origin_y + layout.height - 2
            render_note_section(context, current_row, note_end_row)
            render_footer(context)
          end

          def handle_key(key)
            return handle_cancel if cancel_key?(key)
            return handle_save if save_key?(key)

            if backspace_key?(key)
              handle_backspace
            elsif ["\r", "\n"].include?(key)
              handle_enter
            elsif printable?(key)
              handle_character(key)
            end

            nil
          end

          def handle_click(col, row)
            return nil unless @visible && @button_regions

            @button_regions.each do |key, region|
              next unless row == region[:row]
              next unless col.between?(region[:col], region[:col] + region[:width] - 1)

              return handle_save if key == :save
              return { type: :cancel } if key == :cancel
            end

            nil
          end

          def calculate_width(total_width)
            @overlay_sizing.width_for(total_width)
          end

          def calculate_height(total_height)
            @overlay_sizing.height_for(total_height)
          end

          private

          def render_header(context, row)
            title = "#{panel_fg_emphasis}#{BOLD}Annotation#{RESET_STYLE}#{panel_fg}"
            line = pad_line(title, context[:width], row: row, col: context[:x])
            context[:surface].write(context[:bounds], row, context[:x], line)
            row + 2
          end

          def render_quote(context, start_row)
            text = sanitize_text(@selected_text)
            return start_row if text.empty?

            quote_width = context[:width] - 3
            lines = word_wrap(text, quote_width).first(2)
            render_quote_lines(context, start_row, quote_width, lines)
          end

          def render_note_section(context, start_row, end_row)
            label = "#{glass_fg}#{DIM}Note:#{RESET_STYLE}#{panel_fg}"
            context[:surface].write(
              context[:bounds],
              start_row,
              context[:x],
              pad_line(label, context[:width], row: start_row, col: context[:x])
            )

            note_start = start_row + 1
            note_height = [end_row - note_start, 1].max
            render_note_input(context, note_start, note_height)
          end

          def render_note_input(context, start_row, height)
            text = @note.to_s
            @note_inner_width = context[:width]
            render_state = note_render_state(text, context[:width], height)
            render_state[:start_row] = start_row
            render_state[:cursor_style] = "#{panel_bg}#{panel_fg_emphasis}"
            render_note_input_lines(context, render_state)
            render_spell_suggestion_popup(context, render_state)
          end

          def render_footer(context)
            row = context[:layout].origin_y + context[:layout].height - 1
            hints = if spell_popup_visible?
                      build_spell_footer_hints
                    else
                      "#{glass_fg}#{DIM}Alt+D#{RESET_STYLE}#{panel_fg} spell  " \
                        "#{glass_fg}#{DIM}Ctrl+S#{RESET_STYLE}#{panel_fg} save  " \
                        "#{glass_fg}#{DIM}Esc#{RESET_STYLE}#{panel_fg} cancel"
                    end
            context[:surface].write(
              context[:bounds],
              row,
              context[:x],
              pad_line(hints, context[:width], row: row, col: context[:x])
            )

            @button_regions = {
              save: { row: row, col: context[:x], width: 12 },
              cancel: { row: row, col: context[:x] + 14, width: 10 },
            }
          end

          public

          def handle_backspace
            dismiss_spell_suggestions
            return if @cursor_pos.zero?

            @note = @note[0...(@cursor_pos - 1)] + @note[@cursor_pos..]
            @cursor_pos -= 1
            record_cursor_activity
          end

          def handle_enter
            if spell_popup_visible?
              apply_selected_spell_suggestion
              return nil
            end

            @note, @cursor_pos = Ui::AnnotationListInput.insert_newline(@note, @cursor_pos)
            record_cursor_activity
          end

          def handle_character(char)
            return unless printable?(char)

            dismiss_spell_suggestions
            @note, @cursor_pos = Ui::AnnotationListInput.insert_character(@note, @cursor_pos, char)
            record_cursor_activity
          end

          def handle_move_left
            dismiss_spell_suggestions
            move_cursor { |styler, cursor, width| styler.move_left(cursor, width) }
          end

          def handle_move_right
            dismiss_spell_suggestions
            move_cursor { |styler, cursor, width| styler.move_right(cursor, width) }
          end

          def handle_move_up
            if spell_popup_visible?
              move_spell_suggestion_selection(-1)
              return nil
            end

            move_cursor { |styler, cursor, width| styler.move_up(cursor, width) }
          end

          def handle_move_down
            if spell_popup_visible?
              move_spell_suggestion_selection(1)
              return nil
            end

            move_cursor { |styler, cursor, width| styler.move_down(cursor, width) }
          end

          def handle_save
            { type: :save, note: @note }
          end

          def handle_cancel
            return dismiss_spell_suggestions if spell_popup_visible?

            { type: :cancel }
          end

          def spellcheck_target
            range = current_word_range
            return nil unless range

            {
              word: @note[range[:start]...range[:end]].to_s,
              start: range[:start],
              end: range[:end],
            }
          end

          def show_spell_suggestions(target, suggestions, scope_key: nil, scope_label: nil, can_cycle: false)
            normalized_target = normalize_spell_target(target)
            normalized_suggestions = normalize_spell_suggestions(suggestions)

            if normalized_target.nil?
              dismiss_spell_suggestions
              return nil
            end

            @spell_suggestions = normalized_target.merge(
              suggestions: normalized_suggestions.first(SPELL_SUGGESTION_LIMIT),
              selected_index: 0,
              scope_key: scope_key.to_s.empty? ? nil : scope_key.to_s,
              scope_label: scope_label.to_s.strip,
              can_cycle: can_cycle == true
            )
            record_cursor_activity
            nil
          end

          def spell_suggestion_state
            popup = @spell_suggestions
            return nil unless popup

            {
              word: popup[:word],
              start: popup[:start],
              end: popup[:end],
              scope_key: popup[:scope_key],
              scope_label: popup[:scope_label],
              can_cycle: popup[:can_cycle] == true,
            }
          end

          def dismiss_spell_suggestions
            @spell_suggestions = nil
            nil
          end

          def save_annotation
            handle_save
          end

          def cancel_annotation
            handle_cancel
          end

          private

          def backspace_key?(key)
            BACKSPACE_KEYS.include?(key)
          end

          def save_key?(key)
            SAVE_KEYS.include?(key)
          end

          def cancel_key?(key)
            Shared::KeyDefinitions::ACTIONS[:cancel].include?(key)
          end

          def printable?(key)
            return false unless key.is_a?(String)
            return false if key.length != 1

            cp = key.ord
            return false if cp < 0x20
            return false if cp == 0x7F
            return false if cp.between?(0x80, 0x9F)

            true
          end

          def sanitize_text(text)
            Shoko::Shared::Terminal::TextSanitizer.sanitize(
              text.to_s, preserve_newlines: false, preserve_tabs: false
            ).gsub(/\s+/, ' ').strip
          rescue Shoko::Error
            text.to_s.gsub(/\s+/, ' ').strip
          end

          def word_wrap(text, width)
            return [''] if text.nil? || text.empty? || width <= 0

            lines = []
            text.split("\n", -1).each do |para|
              append_wrapped_paragraph(lines, para, width)
            end

            lines.empty? ? [''] : lines
          end

          def append_wrapped_paragraph(lines, paragraph, width)
            if paragraph.empty?
              lines << ''
              return
            end

            current = ''
            paragraph.split(/\s+/).each do |word|
              current = append_wrapped_word(lines, current, word, width)
            end
            lines << current
          end

          def append_wrapped_word(lines, current, word, width)
            return word if current.empty?
            return "#{current} #{word}" if current.length + 1 + word.length <= width

            lines << current
            word
          end

          def calc_viewport(cursor_line, height, total)
            max_start = [total - height, 0].max
            start = [cursor_line - height + 1, 0].max
            [start, max_start].min
          end

          def pad_line(text, width, row:, col:)
            bg = panel_bg
            len = visible_length(text)
            padding = [width - len, 0].max
            padding_text = backdrop_segment(row, col + len, padding)
            "#{bg}#{panel_fg}#{text}#{backdrop_fg}#{padding_text}#{reset}"
          end

          def move_cursor
            width = @note_inner_width || 40
            styler = Ui::AnnotationMarkup::Styler.new(@note)
            @cursor_pos = yield(styler, @cursor_pos, width)
            record_cursor_activity
          end

          def editor_render_context(surface, bounds, layout)
            {
              surface: surface,
              bounds: bounds,
              layout: layout,
              x: layout.origin_x + PADDING_H,
              width: layout.width - (PADDING_H * 2),
              start_row: layout.origin_y + PADDING_V,
            }
          end

          def fill_editor_background(context)
            bg = panel_bg
            layout = context[:layout]
            layout.height.times do |offset|
              row = layout.origin_y + offset
              backdrop = backdrop_segment(row, layout.origin_x, layout.width)
              context[:surface].write(
                context[:bounds],
                row,
                layout.origin_x,
                "#{bg}#{backdrop_fg}#{backdrop}#{reset}"
              )
            end
          end

          def render_quote_lines(context, start_row, quote_width, lines)
            bg = panel_bg
            qbg = quote_bg
            current_row = start_row
            lines.each do |line|
              padded = line.ljust(quote_width)
              content = "#{bg}#{glass_fg}#{DIM}│#{RESET_STYLE}" \
                        "#{qbg}#{panel_fg_emphasis} #{DIM}#{ITALIC}#{padded}#{RESET_STYLE}" \
                        "#{bg}#{panel_fg}"
              context[:surface].write(context[:bounds], current_row, context[:x], "#{content}#{reset}")
              current_row += 1
            end
            current_row + 1
          end

          def note_viewport(lines, cursor_line_idx, height)
            view_start = calc_viewport(cursor_line_idx, height, lines.length)
            visible = lines[view_start, height] || []
            [visible, cursor_line_idx - view_start, view_start]
          end

          def render_note_input_lines(context, state)
            state[:height].times do |idx|
              row = state[:start_row] + idx
              line_text = state[:styled_visible][idx] || ''
              line_text = cursor_line_text(line_text, idx, context, state)
              context[:surface].write(
                context[:bounds],
                row,
                context[:x],
                pad_line(line_text, context[:width], row: row, col: context[:x])
              )
            end
          end

          def cursor_line_text(line_text, idx, context, state)
            return line_text unless idx == state[:cursor_row]

            inline_cursor_text(
              line_text,
              state[:cursor_col],
              width: context[:width],
              style_prefix: state[:cursor_style],
              restore_prefix: "#{panel_bg}#{panel_fg}"
            )
          end

          def note_render_state(text, width, height)
            renderer = Ui::AnnotationMarkup::Styler.new(text)
            lines = renderer.render_lines(width)
            cursor_line_idx, cursor_col = renderer.cursor_position(@cursor_pos, width)
            visible, cursor_row, view_start = note_viewport(lines, cursor_line_idx, height)
            {
              height: height,
              width: width,
              cursor_col: cursor_col,
              cursor_row: cursor_row,
              view_start: view_start,
              styler: renderer,
              styled_visible: styled_note_lines(visible, text.empty?),
            }
          end

          def render_spell_suggestion_popup(context, state)
            popup = @spell_suggestions
            return unless popup

            anchor_line_idx, anchor_col = state[:styler].cursor_position(popup[:start], state[:width])
            visible_row = anchor_line_idx - state[:view_start]
            return if visible_row.negative? || visible_row >= state[:height]

            rendered_lines, popup_width = spell_popup_lines(popup, state[:width])
            popup_row = spell_popup_row(
              word_row: state[:start_row] + visible_row,
              note_start: state[:start_row],
              note_height: state[:height],
              popup_height: rendered_lines.length
            )
            popup_col = spell_popup_col(
              anchor_col: context[:x] + anchor_col,
              note_x: context[:x],
              note_width: state[:width],
              popup_width: popup_width
            )

            rendered_lines.each_with_index do |line, index|
              context[:surface].write(context[:bounds], popup_row + index, popup_col, line)
            end
          end

          def spell_popup_lines(popup, available_width)
            line_models = spell_popup_line_models(popup)
            inner_width = line_models.map { |line| spell_popup_inner_width(line) }.max.to_i
            popup_width = [[inner_width + 2, SPELL_POPUP_MIN_WIDTH].max, SPELL_POPUP_MAX_WIDTH].min
            popup_width = [popup_width, available_width].min

            rendered = line_models.map do |line|
              spell_popup_line(line, popup_width)
            end

            [rendered, popup_width]
          end

          def spell_popup_line_models(popup)
            suggestions = Array(popup[:suggestions])
            if suggestions.empty?
              return [{ kind: '--', text: 'No suggestions', role: :placeholder, selected: false }]
            end

            suggestions.each_with_index.map do |suggestion, index|
              {
                kind: 'abc',
                text: suggestion,
                role: :suggestion,
                selected: index == popup[:selected_index]
              }
            end
          end

          def spell_popup_inner_width(line)
            kind = line[:kind].to_s
            text = line[:text].to_s
            SPELL_POPUP_KIND_WIDTH + 1 + visible_length(kind) + visible_length(text)
          end

          def spell_popup_line(line, popup_width)
            inner_width = [popup_width - 2, 1].max
            kind_width = [SPELL_POPUP_KIND_WIDTH, inner_width - 2].min
            gap_width = inner_width > kind_width ? 1 : 0
            text_width = [inner_width - kind_width - gap_width, 1].max
            kind = Shoko::Shared::Terminal::TextMetrics.truncate_to(line[:kind].to_s, kind_width).ljust(kind_width)
            text = Shoko::Shared::Terminal::TextMetrics.truncate_to(line[:text].to_s, text_width)
            text_padding = [text_width - visible_length(text), 0].max
            row_bg = line[:selected] ? spell_menu_selected_bg : spell_menu_bg
            row_fg = spell_popup_text_fg(line[:role], selected: line[:selected])
            kind_fg = spell_popup_kind_fg(line[:role], selected: line[:selected])

            "#{row_bg} " \
              "#{kind_fg}#{kind}" \
              "#{row_bg} " \
              "#{row_fg}#{text}#{' ' * text_padding}" \
              "#{row_bg} #{reset}"
          end

          def spell_popup_text_fg(role, selected:)
            return spell_menu_selected_fg if selected

            role == :placeholder ? spell_menu_muted_fg : spell_menu_fg
          end

          def spell_popup_kind_fg(role, selected:)
            return spell_menu_selected_fg if selected

            role == :placeholder ? spell_menu_muted_fg : spell_menu_kind_fg
          end

          def spell_popup_row(word_row:, note_start:, note_height:, popup_height:)
            max_row = note_start + note_height - popup_height
            below_row = word_row + 1
            return below_row if below_row <= max_row

            above_row = word_row - popup_height
            return above_row if above_row >= note_start

            [[below_row, note_start].max, max_row].min
          end

          def spell_popup_col(anchor_col:, note_x:, note_width:, popup_width:)
            min_col = note_x
            max_col = note_x + note_width - popup_width
            preferred_col = anchor_col - 1
            [[preferred_col, min_col].max, max_col].min
          end

          def spell_popup_visible?
            popup = @spell_suggestions
            !popup.nil?
          end

          def apply_selected_spell_suggestion
            popup = @spell_suggestions
            return dismiss_spell_suggestions unless popup

            suggestion = Array(popup[:suggestions])[popup[:selected_index]]
            return dismiss_spell_suggestions if suggestion.to_s.empty?

            @note = @note[0...popup[:start]] + suggestion + @note[popup[:end]..]
            @cursor_pos = popup[:start] + suggestion.length
            dismiss_spell_suggestions
            record_cursor_activity
          end

          def move_spell_suggestion_selection(delta)
            popup = @spell_suggestions
            return unless popup

            suggestions = Array(popup[:suggestions])
            return if suggestions.empty?

            popup[:selected_index] = (popup[:selected_index].to_i + delta) % suggestions.length
            record_cursor_activity
          end

          def normalize_spell_target(target)
            return nil unless target.is_a?(Hash)

            start_index = integer_value(target[:start] || target['start'])
            end_index = integer_value(target[:end] || target['end'])
            return nil unless start_index && end_index
            return nil if end_index <= start_index

            word = @note[start_index...end_index].to_s
            return nil unless word.match?(WORD_CONTENT)

            { word: word, start: start_index, end: end_index }
          end

          def normalize_spell_suggestions(suggestions)
            Array(suggestions)
              .map { |value| value.to_s.strip }
              .reject(&:empty?)
              .each_with_object([]) do |value, normalized|
                next if normalized.any? { |existing| existing.casecmp(value).zero? }

                normalized << value
              end
          end

          def build_spell_footer_hints
            popup = @spell_suggestions || {}
            scope_label = popup[:scope_label].to_s.strip
            scope_hint = if scope_label.empty?
                           ''
                         else
                           "#{glass_fg}#{DIM}[#{scope_label}]#{RESET_STYLE}#{panel_fg}  "
                         end
            choose_hint = if Array(popup[:suggestions]).any?
                            "#{glass_fg}#{DIM}↑↓#{RESET_STYLE}#{panel_fg} choose  " \
                              "#{glass_fg}#{DIM}Enter#{RESET_STYLE}#{panel_fg} replace  "
                          else
                            ''
                          end
            cycle_hint = if popup[:can_cycle] == true
                           "#{glass_fg}#{DIM}Alt+D#{RESET_STYLE}#{panel_fg} next dict  "
                         else
                           ''
                         end

            "#{scope_hint}#{choose_hint}#{cycle_hint}#{glass_fg}#{DIM}Esc#{RESET_STYLE}#{panel_fg} dismiss"
          end

          def current_word_range
            text = @note.to_s
            return nil if text.empty?

            cursor = @cursor_pos.to_i.clamp(0, text.length)
            anchor = if cursor.positive? && word_character?(text[cursor - 1])
                       cursor - 1
                     elsif word_character?(text[cursor])
                       cursor
                     end
            return nil unless anchor

            start_index = anchor
            start_index -= 1 while start_index.positive? && word_character?(text[start_index - 1])

            end_index = anchor + 1
            end_index += 1 while end_index < text.length && word_character?(text[end_index])

            word = text[start_index...end_index].to_s
            return nil unless word.match?(WORD_CONTENT)

            { start: start_index, end: end_index }
          end

          def word_character?(char)
            return false unless char.is_a?(String)

            char.match?(WORD_CHARACTER)
          end

          def integer_value(value)
            Shoko::Shared::TypeCoercion.optional_integer(value)
          end

          def styled_note_lines(lines, empty_text)
            styled = lines.map { |line| line + Ui::AnnotationMarkup::STYLE_RESET }
            styled[0] = "#{glass_fg}#{DIM}Write your annotation...#{RESET_STYLE}#{panel_fg}" if empty_text
            styled
          end

          def visible_length(text)
            Shoko::Shared::Terminal::TextMetrics.visible_length(text.to_s)
          rescue Shoko::Error
            text.to_s.gsub(/\e\[[0-9;]*m/, '').length
          end

          def overlay_layout(bounds)
            w = @overlay_sizing.width_for(bounds.width)
            h = @overlay_sizing.height_for(bounds.height)
            Ui::OverlayLayout.centered(bounds, width: w, height: h)
          end

          def backdrop_segment(row, col, width)
            return '' if width <= 0

            cell_map = backdrop_cells_for_row(row)
            col_start = col.to_i
            col_end = col_start + width
            (col_start...col_end).map do |column|
              value = cell_map[column]
              next ' ' if value.nil? || value == :continuation

              backdrop_char(value)
            end.join
          end

          def backdrop_char(value)
            char = value.to_s
            return ' ' if char.empty? || char == ' '

            char
          end

          def backdrop_cells_for_row(row)
            cache = backdrop_row_cache
            return cache[row] if cache.key?(row)

            cache[row] = build_backdrop_cells(row)
          end

          def build_backdrop_cells(row)
            geometries_for_row(row).each_with_object({}) do |geometry, cells|
              merge_geometry_cells(cells, geometry)
            end
          end

          def geometries_for_row(row)
            lines = @rendered_lines
            return [] unless lines.is_a?(Hash)

            geometries = lines.each_value.filter_map do |entry|
              geometry = entry && entry[:geometry]
              next unless geometry
              next unless geometry.row.to_i == row.to_i

              geometry
            end

            geometries.sort_by { |geometry| geometry.column_origin.to_i }
          end

          def merge_geometry_cells(cells, geometry)
            Array(geometry.cells).each do |cell|
              merge_cell(cells, geometry, cell)
            end
          end

          def merge_cell(cells, geometry, cell)
            width = cell.display_width.to_i
            return if width <= 0

            absolute_column = geometry.column_origin.to_i + cell.screen_x.to_i
            cluster = cell.cluster.to_s
            cells[absolute_column] = cluster.empty? ? ' ' : cluster
            mark_continuation_cells(cells, absolute_column, width)
          end

          def mark_continuation_cells(cells, absolute_column, width)
            1.upto(width - 1) do |delta|
              cells[absolute_column + delta] = :continuation
            end
          end

          def backdrop_row_cache
            lines = @rendered_lines
            key = lines.object_id
            return @backdrop_rows if @backdrop_rows_key == key

            @backdrop_rows_key = key
            @backdrop_rows = {}
          end

          attr_reader :color_mode

          def panel_bg
            color_mode == :light ? PANEL_BG_LIGHT : TOOLTIP_BG_DEFAULT
          end

          def quote_bg
            color_mode == :light ? QUOTE_BG_LIGHT : TOOLTIP_BG_SELECTED
          end

          def panel_fg
            color_mode == :light ? PANEL_FG_LIGHT : TOOLTIP_FG_DEFAULT
          end

          def panel_fg_emphasis
            color_mode == :light ? PANEL_FG_EMPHASIS_LIGHT : TOOLTIP_FG_SELECTED
          end

          def glass_fg
            color_mode == :light ? GLASS_FG_LIGHT : TOOLTIP_GLASS_FG_DEFAULT
          end

          def spell_menu_bg
            color_mode == :light ? SPELL_MENU_BG_LIGHT : SPELL_MENU_BG_DARK
          end

          def spell_menu_selected_bg
            color_mode == :light ? SPELL_MENU_SELECTED_BG_LIGHT : SPELL_MENU_SELECTED_BG_DARK
          end

          def spell_menu_fg
            color_mode == :light ? SPELL_MENU_FG_LIGHT : SPELL_MENU_FG_DARK
          end

          def spell_menu_selected_fg
            color_mode == :light ? SPELL_MENU_SELECTED_FG_LIGHT : SPELL_MENU_SELECTED_FG_DARK
          end

          def spell_menu_kind_fg
            color_mode == :light ? SPELL_MENU_KIND_FG_LIGHT : SPELL_MENU_KIND_FG_DARK
          end

          def spell_menu_muted_fg
            color_mode == :light ? SPELL_MENU_MUTED_FG_LIGHT : SPELL_MENU_MUTED_FG_DARK
          end

          def backdrop_fg
            color_mode == :light ? BACKDROP_FG_LIGHT : BACKDROP_FG_DARK
          end

          def reset
            Shoko::Shared::Terminal::Ansi::RESET
          end
        end
      end
    end
  end
end
