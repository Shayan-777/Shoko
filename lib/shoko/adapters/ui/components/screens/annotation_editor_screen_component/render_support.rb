# frozen_string_literal: true

require_relative '../../../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Rendering helpers for the reader-context annotation editor screen.
          module AnnotationEditorScreenRenderSupport
            include Adapters::Ui::Constants::Ui

            private

            def render_body
              text_box = selected_text_box
              render_text_box(text_box)
              render_note_box(note_box(text_box))
            end

            def selected_text_box
              AnnotationTextBox.new(
                row: 4,
                height: [context.height * 0.25, 6].max.to_i,
                width: context.width - 4,
                label: 'Selected Text',
                text: context.selected_text
              )
            end

            def note_box(text_box)
              text_box.next_box(
                total_height: context.height,
                label: 'Note (editable)',
                text: context.note_text,
                style: :markup
              )
            end

            def render_text_box(box)
              box.render(context, drawer: self, color_prefix: COLOR_TEXT_PRIMARY)
            end

            def render_note_box(box)
              @note_inner_width = box.inner_width
              render_text_box(box)
              render_inline_cursor(box)
            end

            def render_inline_cursor(box)
              cursor = inline_cursor_position(box)
              return unless cursor

              write_inline_cursor(box, cursor)
            end

            def inline_cursor_position(box)
              row, col = box.cursor_position(@cursor_pos)
              visible_row = row - (box.row + 1)
              return nil if visible_row.negative? || visible_row >= (box.height - 2)

              {
                row: row,
                column: col - AnnotationTextBox::TEXT_COLUMN,
                display_line: cursor_display_line(box, visible_row),
              }
            end

            def cursor_display_line(box, visible_row)
              source_line = box_line_text(box, visible_row)
              return source_line unless box.style == :markup

              "#{source_line}#{Ui::AnnotationMarkup::STYLE_RESET}"
            end

            def write_inline_cursor(box, cursor)
              with_cursor = inline_cursor_text(
                cursor[:display_line],
                cursor[:column],
                width: box.inner_width,
                style_prefix: SELECTION_HIGHLIGHT,
                restore_prefix: COLOR_TEXT_PRIMARY
              )
              padded = Ui::TextUtils.pad_right(with_cursor, box.inner_width)
              context.surface.write(
                context.bounds,
                cursor[:row],
                AnnotationTextBox::TEXT_COLUMN,
                "#{COLOR_TEXT_PRIMARY}#{padded}#{context.reset}"
              )
            end
          end
        end
      end
    end
  end
end
