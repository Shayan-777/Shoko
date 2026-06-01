# frozen_string_literal: true

require_relative '../../../shared/type_coercion'
require_relative 'base_component'
require_relative 'ui/backdrop_overlay'
require_relative 'ui/overlay_layout'
require_relative 'ui/annotation_markup'
require_relative '../../../shared/annotation_list_input'
require_relative 'ui/cursor_blink'
require_relative '../../../shared/terminal/text_metrics'
require_relative '../../../shared/terminal/ansi'
require_relative '../../../shared/key_definitions'
require_relative '../../../shared/terminal/text_sanitizer'
require_relative '../constants/component_palettes'
require_relative 'ui/list_helpers'

module Shoko
  module Adapters
    module Ui
      module Components
        # Overlay for creating/editing annotations.
        class AnnotationEditorOverlayComponent < BaseComponent
          include Adapters::Ui::Constants::Ui
          include Ui::CursorBlink

          SAVE_KEYS = ["\x13"].freeze # Ctrl+S
          BACKSPACE_KEYS = ["\x08", "\x7F", "\b"].freeze
          SPELL_SUGGESTION_LIMIT = 5
          SPELL_POPUP_MIN_WIDTH = 18
          SPELL_POPUP_MAX_WIDTH = 34
          SPELL_POPUP_KIND_WIDTH = 3
          WORD_CHARACTER = /\A[\p{L}\p{M}\p{N}'’-]\z/
          WORD_CONTENT = /[\p{L}\p{N}]/

          BOLD = "\e[1m"
          DIM = "\e[2m"
          ITALIC = "\e[3m"
          RESET_STYLE = "\e[22;23;24m"

          PADDING_H = 2
          PADDING_V = 1

          attr_reader :visible

          def initialize(reader_state_reader:, reader_session_mutator:, color_mode: :dark, rendered_lines: nil)
            super()
            @reader_state_reader = reader_state_reader
            @reader_session_mutator = reader_session_mutator
            @color_mode = normalize_color_mode(color_mode)
            @backdrop_overlay = Ui::BackdropOverlay.new(rendered_lines: rendered_lines)
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
            @color_mode = normalize_color_mode(mode)
          end

          def update_rendered_lines(rendered_lines)
            @backdrop_overlay.update_rendered_lines(rendered_lines)
          end

          def note
            (@reader_state_reader&.annotation_editor_note || '').to_s
          end

          def cursor_pos
            value = @reader_state_reader&.annotation_editor_cursor
            value.nil? ? note.length : value.to_i
          end

          def selected_text
            (@reader_state_reader&.annotation_editor_selected_text || '').to_s
          end

          def chapter_index
            @reader_state_reader&.annotation_editor_chapter_index
          end

          def annotation_id
            @reader_state_reader&.annotation_editor_annotation_id
          end

          def selection_range
            @reader_state_reader&.annotation_editor_range
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

          def handle_backspace
            dismiss_spell_suggestions
            current_cursor = cursor_pos
            return if current_cursor.zero?

            current_note = note
            updated_note = current_note[0...(current_cursor - 1)] + current_note[current_cursor..].to_s
            write_note(updated_note, current_cursor - 1)
          end

          def handle_enter
            if spell_popup_visible?
              apply_selected_spell_suggestion
              return nil
            end

            updated_note, updated_cursor = Shoko::Shared::AnnotationListInput.insert_newline(note, cursor_pos)
            write_note(updated_note, updated_cursor)
          end

          def handle_character(char)
            return unless printable?(char)

            dismiss_spell_suggestions
            updated_note, updated_cursor = Shoko::Shared::AnnotationListInput.insert_character(note, cursor_pos, char)
            write_note(updated_note, updated_cursor)
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
            { type: :save, note: note }
          end

          def handle_cancel
            return dismiss_spell_suggestions if spell_popup_visible?

            { type: :cancel }
          end

          def save_annotation
            handle_save
          end

          def cancel_annotation
            handle_cancel
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


          def spellcheck_target
            range = current_word_range
            return nil unless range

            {
              word: note[range[:start]...range[:end]].to_s,
              start: range[:start],
              end: range[:end],
            }
          end


          private

          def write_note(text, cursor)
            @reader_session_mutator&.update_reader(
              annotation_editor_note: text,
              annotation_editor_cursor: cursor
            )
            record_cursor_activity
          end


          def render_header(context, row)
            title = "#{panel_fg_emphasis}#{BOLD}Annotation#{RESET_STYLE}#{panel_fg}"
            line = pad_line(title, context[:width], row: row, col: context[:x])
            context[:surface].write(context[:bounds], row, context[:x], line)
            row + 2
          end

          def render_quote(context, start_row)
            text = sanitize_text(selected_text)
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
            text = note.to_s
            @note_inner_width = context[:width]
            render_state = note_render_state(text, context[:width], height)
            render_state[:start_row] = start_row
            render_state[:cursor_style] = "#{panel_bg}#{panel_fg_emphasis}"
            render_note_input_lines(context, render_state)
            render_spell_suggestion_popup(context, render_state)
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
            text.split("\n", -1).each do |paragraph|
              append_wrapped_paragraph(lines, paragraph, width)
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
            current_note = note
            current_cursor = cursor_pos
            styler = Ui::AnnotationMarkup::Styler.new(current_note)
            new_cursor = yield(styler, current_cursor, width)
            return if new_cursor == current_cursor

            @reader_session_mutator&.update_reader(annotation_editor_cursor: new_cursor)
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
            cursor_line_idx, cursor_col = renderer.cursor_position(cursor_pos, width)
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


          def render_footer(context)
            row = context[:layout].origin_y + context[:layout].height - 1
            context[:surface].write(
              context[:bounds],
              row,
              context[:x],
              pad_line(footer_hints_text, context[:width], row: row, col: context[:x])
            )
            @button_regions = footer_button_regions(context[:x], row)
          end

          def footer_hints_text
            return build_spell_footer_hints if spell_popup_visible?

            "#{glass_fg}#{DIM}Alt+D#{RESET_STYLE}#{panel_fg} spell  " \
              "#{glass_fg}#{DIM}Ctrl+S#{RESET_STYLE}#{panel_fg} save  " \
              "#{glass_fg}#{DIM}Esc#{RESET_STYLE}#{panel_fg} cancel"
          end

          def footer_button_regions(start_col, row)
            {
              save: { row: row, col: start_col, width: 12 },
              cancel: { row: row, col: start_col + 14, width: 10 },
            }
          end


          def overlay_layout(bounds)
            width = @overlay_sizing.width_for(bounds.width)
            height = @overlay_sizing.height_for(bounds.height)
            Ui::OverlayLayout.centered(bounds, width: width, height: height)
          end

          def backdrop_segment(row, col, width)
            @backdrop_overlay.segment(row, col, width)
          end

          def panel_bg
            overlay_palette[:panel_bg]
          end

          def quote_bg
            overlay_palette[:quote_bg]
          end

          def panel_fg
            overlay_palette[:panel_fg]
          end

          def panel_fg_emphasis
            overlay_palette[:panel_fg_emphasis]
          end

          def glass_fg
            overlay_palette[:glass_fg]
          end

          def spell_menu_bg
            overlay_palette[:spell_menu_bg]
          end

          def spell_menu_selected_bg
            overlay_palette[:spell_menu_selected_bg]
          end

          def spell_menu_fg
            overlay_palette[:spell_menu_fg]
          end

          def spell_menu_selected_fg
            overlay_palette[:spell_menu_selected_fg]
          end

          def spell_menu_kind_fg
            overlay_palette[:spell_menu_kind_fg]
          end

          def spell_menu_muted_fg
            overlay_palette[:spell_menu_muted_fg]
          end

          def backdrop_fg
            overlay_palette[:backdrop_fg]
          end

          def color_mode
            @color_mode
          end

          def overlay_palette
            Adapters::Ui::Constants::ComponentPalettes.fetch(:annotation_editor_overlay, color_mode)
          end

          def reset
            Shoko::Shared::Terminal::Ansi::RESET
          end


          def spell_popup_visible?
            !@spell_suggestions.nil?
          end

          def apply_selected_spell_suggestion
            popup = @spell_suggestions
            return dismiss_spell_suggestions unless popup

            suggestion = Array(popup[:suggestions])[popup[:selected_index]]
            return dismiss_spell_suggestions if suggestion.to_s.empty?

            current_note = note
            updated_note = current_note[0...popup[:start]] + suggestion + current_note[popup[:end]..].to_s
            updated_cursor = popup[:start] + suggestion.length
            @reader_session_mutator&.update_reader(
              annotation_editor_note: updated_note,
              annotation_editor_cursor: updated_cursor
            )
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

            normalized = symbolize_hash(target)
            start_index = integer_value(normalized[:start])
            end_index = integer_value(normalized[:end])
            return nil unless start_index && end_index
            return nil if end_index <= start_index

            word = note[start_index...end_index].to_s
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

          def word_character?(char)
            return false unless char.is_a?(String)

            char.match?(WORD_CHARACTER)
          end

          def integer_value(value)
            Shoko::Shared::TypeCoercion.optional_integer(value)
          end

          def render_spell_suggestion_popup(context, state)
            popup = @spell_suggestions
            return unless popup

            payload = spell_popup_render_payload(context, state, popup)
            return unless payload

            write_spell_popup_lines(context, payload)
          end

          def spell_popup_anchor(state, popup)
            anchor_line_idx, anchor_col = state[:styler].cursor_position(popup[:start], state[:width])
            visible_row = anchor_line_idx - state[:view_start]
            return nil if visible_row.negative? || visible_row >= state[:height]

            { visible_row: visible_row, anchor_col: anchor_col }
          end

          def spell_popup_render_payload(context, state, popup)
            anchor = spell_popup_anchor(state, popup)
            return nil unless anchor

            rendered_lines, popup_width = spell_popup_lines(
              popup,
              available_width: state[:width],
              available_height: spell_popup_available_height(state)
            )
            {
              lines: rendered_lines,
              row: spell_popup_render_row(state, anchor, rendered_lines.length),
              col: spell_popup_render_col(context, state, anchor, popup_width),
            }
          end

          def spell_popup_render_row(state, anchor, popup_height)
            spell_popup_row(
              word_row: state[:start_row] + anchor[:visible_row],
              note_start: state[:start_row],
              note_height: state[:height],
              popup_height: popup_height
            )
          end

          def spell_popup_render_col(context, state, anchor, popup_width)
            spell_popup_col(
              anchor_col: context[:x] + anchor[:anchor_col],
              note_x: context[:x],
              note_width: state[:width],
              popup_width: popup_width
            )
          end

          def write_spell_popup_lines(context, payload)
            payload[:lines].each_with_index do |line, index|
              context[:surface].write(context[:bounds], payload[:row] + index, payload[:col], line)
            end
          end

          def spell_popup_lines(popup, available_width:, available_height:)
            line_models = spell_popup_line_models(popup, available_height)
            popup_width = spell_popup_width(line_models, available_width)
            rendered = line_models.map { |line| spell_popup_line(line, popup_width) }
            [rendered, popup_width]
          end

          def spell_popup_width(line_models, available_width)
            inner_width = line_models.map { |line| spell_popup_inner_width(line) }.max.to_i
            desired_width = (inner_width + 2).clamp(SPELL_POPUP_MIN_WIDTH, SPELL_POPUP_MAX_WIDTH)
            [desired_width, available_width].min
          end

          def spell_popup_available_height(state)
            [state[:height].to_i, 1].max
          end

          def spell_popup_line_models(popup, max_lines)
            suggestions = Array(popup[:suggestions])
            return [empty_spell_popup_line] if suggestions.empty?

            start_index, visible_suggestions = Ui::ListHelpers.slice_visible(
              suggestions,
              [max_lines, 1].max,
              popup[:selected_index].to_i
            )

            visible_suggestions.each_with_index.map do |suggestion, index|
              spell_popup_line_model(suggestion, start_index + index == popup[:selected_index].to_i)
            end
          end

          def empty_spell_popup_line
            { kind: '--', text: 'No suggestions', role: :placeholder, selected: false }
          end

          def spell_popup_line_model(suggestion, selected)
            {
              kind: 'abc',
              text: suggestion,
              role: :suggestion,
              selected: selected,
            }
          end

          def spell_popup_inner_width(line)
            kind = line[:kind].to_s
            text = line[:text].to_s
            SPELL_POPUP_KIND_WIDTH + 1 + visible_length(kind) + visible_length(text)
          end

          def spell_popup_line(line, popup_width)
            layout = spell_popup_line_layout(popup_width)
            content = spell_popup_line_content(line, layout)
            palette = spell_popup_line_palette(line)

            "#{palette[:row_bg]} " \
              "#{palette[:kind_fg]}#{content[:kind]}" \
              "#{palette[:row_bg]} " \
              "#{palette[:row_fg]}#{content[:text]}#{content[:padding]}" \
              "#{palette[:row_bg]} #{reset}"
          end

          def spell_popup_line_layout(popup_width)
            inner_width = [popup_width - 2, 1].max
            kind_width = [SPELL_POPUP_KIND_WIDTH, inner_width - 2].min
            gap_width = inner_width > kind_width ? 1 : 0
            text_width = [inner_width - kind_width - gap_width, 1].max
            { kind_width: kind_width, text_width: text_width }
          end

          def spell_popup_line_content(line, layout)
            kind = Shoko::Shared::Terminal::TextMetrics
                   .truncate_to(line[:kind].to_s, layout[:kind_width])
                   .ljust(layout[:kind_width])
            text = Shoko::Shared::Terminal::TextMetrics.truncate_to(line[:text].to_s, layout[:text_width])
            padding = ' ' * [layout[:text_width] - visible_length(text), 0].max
            { kind: kind, text: text, padding: padding }
          end

          def spell_popup_line_palette(line)
            selected = line[:selected]
            role = line[:role]
            {
              row_bg: selected ? spell_menu_selected_bg : spell_menu_bg,
              row_fg: spell_popup_text_fg(role, selected: selected),
              kind_fg: spell_popup_kind_fg(role, selected: selected),
            }
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
            return note_start if max_row < note_start

            below_row = word_row + 1
            return below_row if below_row <= max_row

            above_row = word_row - popup_height
            return above_row if above_row >= note_start

            below_row.clamp(note_start, max_row)
          end

          def spell_popup_col(anchor_col:, note_x:, note_width:, popup_width:)
            min_col = note_x
            max_col = note_x + note_width - popup_width
            preferred_col = anchor_col - 1
            preferred_col.clamp(min_col, max_col)
          end

          def build_spell_footer_hints
            popup = @spell_suggestions || {}
            [
              spell_footer_scope_hint(popup),
              spell_footer_choose_hint(popup),
              spell_footer_cycle_hint(popup),
              "#{glass_fg}#{DIM}Esc#{RESET_STYLE}#{panel_fg} dismiss",
            ].join
          end

          def spell_footer_scope_hint(popup)
            scope_label = popup[:scope_label].to_s.strip
            return '' if scope_label.empty?

            "#{glass_fg}#{DIM}[#{scope_label}]#{RESET_STYLE}#{panel_fg}  "
          end

          def spell_footer_choose_hint(popup)
            return '' unless Array(popup[:suggestions]).any?

            "#{glass_fg}#{DIM}↑↓#{RESET_STYLE}#{panel_fg} choose  " \
              "#{glass_fg}#{DIM}Enter#{RESET_STYLE}#{panel_fg} replace  "
          end

          def spell_footer_cycle_hint(popup)
            return '' unless popup[:can_cycle] == true

            "#{glass_fg}#{DIM}Alt+D#{RESET_STYLE}#{panel_fg} next dict  "
          end


          def current_word_range
            text = note.to_s
            return nil if text.empty?

            anchor = word_anchor(text)
            return nil unless anchor

            start_index = word_start_index(text, anchor)
            end_index = word_end_index(text, anchor)
            valid_word_range(text, start_index, end_index)
          end

          def word_anchor(text)
            cursor = cursor_pos.to_i.clamp(0, text.length)
            return cursor - 1 if cursor.positive? && word_character?(text[cursor - 1])
            return cursor if word_character?(text[cursor])

            nil
          end

          def word_start_index(text, anchor)
            start_index = anchor
            start_index -= 1 while start_index.positive? && word_character?(text[start_index - 1])
            start_index
          end

          def word_end_index(text, anchor)
            end_index = anchor + 1
            end_index += 1 while end_index < text.length && word_character?(text[end_index])
            end_index
          end

          def valid_word_range(text, start_index, end_index)
            word = text[start_index...end_index].to_s
            return nil unless word.match?(WORD_CONTENT)

            { start: start_index, end: end_index }
          end


          def normalize_color_mode(mode)
            mode.to_s == 'light' ? :light : :dark
          end

          def backspace_key?(key)
            self.class::BACKSPACE_KEYS.include?(key)
          end

          def save_key?(key)
            self.class::SAVE_KEYS.include?(key)
          end

          def cancel_key?(key)
            Shared::KeyDefinitions::ACTIONS[:cancel].include?(key)
          end

          def printable?(key)
            return false unless key.is_a?(String)
            return false if key.length != 1

            codepoint = key.ord
            return false if codepoint < 0x20
            return false if codepoint == 0x7F
            return false if codepoint.between?(0x80, 0x9F)

            true
          end

          def symbolize_hash(value)
            return {} unless value.is_a?(Hash)

            value.transform_keys do |key|
              key.is_a?(String) ? key.to_sym : key
            end
          end

        end
      end
    end
  end
end
