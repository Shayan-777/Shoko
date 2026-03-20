# frozen_string_literal: true

require_relative '../../base_component'
require_relative '../../ui/list_helpers'

module Shoko
  module Adapters
    module Ui
      module Components
        class AnnotationEditorOverlayComponent < BaseComponent
          module SpellSupport
            # Popup layout and rendering helpers for spell suggestions.
            module PopupRendering
              private

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
            end
          end
        end
      end
    end
  end
end
