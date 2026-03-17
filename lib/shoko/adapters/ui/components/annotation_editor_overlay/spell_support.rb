# frozen_string_literal: true

require_relative '../base_component'

module Shoko
  module Adapters
    module Ui
      module Components
        class AnnotationEditorOverlayComponent < BaseComponent
          # Spell-suggestion state and popup rendering for the annotation editor.
          module SpellSupport
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

            private

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
              !@spell_suggestions.nil?
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

              normalized = symbolize_hash(target)
              start_index = integer_value(normalized[:start])
              end_index = integer_value(normalized[:end])
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

            def symbolize_hash(value)
              value.each_with_object({}) do |(key, inner_value), normalized|
                normalized[key.is_a?(String) ? key.to_sym : key] = inner_value
              end
            end
          end
        end
      end
    end
  end
end
