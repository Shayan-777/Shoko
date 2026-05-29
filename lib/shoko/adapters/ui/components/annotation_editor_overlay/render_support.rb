# frozen_string_literal: true

require_relative '../base_component'
require_relative 'render_support/footer_support'
require_relative 'render_support/palette_support'

module Shoko
  module Adapters
    module Ui
      module Components
        class AnnotationEditorOverlayComponent < BaseComponent
          # Rendering and layout helpers for the annotation editor overlay.
          module RenderSupport
            include FooterSupport
            include PaletteSupport

            private

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
          end
        end
      end
    end
  end
end
