# frozen_string_literal: true

require_relative '../ui/text_utils'
require_relative '../../../../shared/terminal/text_metrics'
require_relative '../../../../shared/terminal/device'

module Shoko
  module Adapters::Ui::Components
    # Namespace for annotation editor overlay helpers.
    module AnnotationEditorOverlay
      # Renders note contents and cursor inside the annotation editor overlay.
      class NoteRenderer
        def initialize(background:, text_color:, cursor_color:, geometry:, placeholder_text: nil,
                       placeholder_color: nil)
          @background = background
          @text_color = text_color
          @cursor_color = cursor_color
          @geometry = geometry
          @placeholder_text = placeholder_text
          @placeholder_color = placeholder_color
        end

        def render(surface, bounds, note:, cursor_pos:)
          note_text = note.to_s
          wrapped_note = wrap_lines(note_text, @geometry.text_width)
          cursor_lines = wrap_lines(note_text[0...cursor_pos], @geometry.text_width)
          cursor_line_index = [cursor_lines.length - 1, 0].max

          visible_start, visible_lines = visible_window(wrapped_note, cursor_line_index, @geometry.note_rows)
          render_lines(surface, bounds, visible_lines)
          render_placeholder(surface, bounds) if note_text.strip.empty?
          cursor_row, cursor_col = cursor_position(cursor_lines, cursor_line_index, visible_start)
          render_cursor(surface, bounds, cursor_row, cursor_col)
        end

        private

        def wrap_lines(text, width)
          lines = Ui::TextUtils.wrap_text(text.to_s, width)
          lines.empty? ? [''] : lines
        end

        def visible_window(lines, cursor_line_index, note_rows)
          max_start = [lines.length - note_rows, 0].max
          visible_start = [cursor_line_index - note_rows + 1, 0].max
          visible_start = [visible_start, max_start].min
          visible_lines = lines[visible_start, note_rows] || []
          visible_lines += Array.new(note_rows - visible_lines.length, '')
          [visible_start, visible_lines]
        end

        def render_lines(surface, bounds, lines)
          lines.each_with_index do |line, idx|
            row = @geometry.note_top + idx
            padded = Ui::TextUtils.pad_right(line, @geometry.text_width)
            surface.write(bounds, row, @geometry.text_x,
                          "#{@background}#{@text_color}#{padded}#{Terminal::ANSI::RESET}")
          end
        end

        def render_placeholder(surface, bounds)
          return unless @placeholder_text && @placeholder_color

          truncated = Shoko::Shared::Terminal::TextMetrics.truncate_to(@placeholder_text,
                                                                                 @geometry.text_width)
          padded = Ui::TextUtils.pad_right(truncated, @geometry.text_width)
          surface.write(bounds, @geometry.note_top, @geometry.text_x,
                        "#{@background}#{@placeholder_color}#{padded}#{Terminal::ANSI::RESET}")
        end

        def cursor_position(cursor_lines, cursor_line_index, visible_start)
          cursor_display_row = (cursor_line_index - visible_start).clamp(0, @geometry.note_rows - 1)
          cursor_row = @geometry.note_top + cursor_display_row
          cursor_line = cursor_lines.last || ''
          cursor_col = @geometry.text_x + [Shoko::Shared::Terminal::TextMetrics.visible_length(cursor_line),
                                           @geometry.text_width - 1].min
          [cursor_row, cursor_col]
        end

        def render_cursor(surface, bounds, cursor_row, cursor_col)
          surface.write(bounds, cursor_row, cursor_col,
                        "#{@background}#{@cursor_color}|#{Terminal::ANSI::RESET}")
        end
      end
    end
  end
end
