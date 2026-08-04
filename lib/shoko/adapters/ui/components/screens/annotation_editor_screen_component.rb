# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui'
require_relative '../ui/box_drawer'
require_relative '../ui/cursor_blink'
require 'shoko/core/services/annotation_list_input'
require_relative 'annotation_text_box'
require 'shoko/core/models/annotation_draft'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Reader-context annotation editor as a proper component
          # Replaces ReaderModes::AnnotationEditorMode
          class AnnotationEditorScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::BoxDrawer
            include Ui::CursorBlink

            # Rendering context for this screen to avoid parameter clumps.
            RenderContext = Struct.new(:surface, :bounds, :width, :height, :reset, :selected_text, :note_text)

            def initialize(ui_controller, text: nil, annotation: nil, chapter_index: nil,
                           annotation_service: nil)
              super()
              @ui = ui_controller
              @annotation_service = annotation_service
              @annotation = annotation
              @selected_text = (text || annotation&.fetch('text', '') || '').dup
              @note = (annotation&.fetch('note', '') || '').dup
              @chapter_index = chapter_index || annotation&.fetch('chapter_index', nil)
              @cursor_pos = @note.length
              @is_editing = !annotation.nil?
              @render_context = nil
              @note_inner_width = nil
              initialize_cursor_blink
            end

            def do_render(surface, bounds)
              @render_context = build_context(surface, bounds)
              render_header
              render_body
              render_footer
            ensure
              @render_context = nil
            end

            # Public API used by InputController bindings
            def save_annotation
              path = @ui.current_book_path
              service = @annotation_service
              return unless path && service

              persist_annotation(service, path)
              finalize_save
            end

            def handle_backspace
              return unless @cursor_pos.positive?

              @note.slice!(@cursor_pos - 1)
              @cursor_pos -= 1
              record_cursor_activity
            end

            def handle_enter
              @note, @cursor_pos = Shoko::Core::Services::AnnotationListInput.insert_newline(@note, @cursor_pos)
              record_cursor_activity
            end

            def handle_character(key)
              ord = key.ord
              return unless key.to_s.length == 1 && ord >= 32 && ord < 127

              @note, @cursor_pos = Shoko::Core::Services::AnnotationListInput.insert_character(@note, @cursor_pos, key)
              record_cursor_activity
            end

            def handle_move_left
              move_cursor { |styler, cursor, width| styler.move_left(cursor, width) }
            end

            def handle_move_right
              move_cursor { |styler, cursor, width| styler.move_right(cursor, width) }
            end

            def handle_move_up
              move_cursor { |styler, cursor, width| styler.move_up(cursor, width) }
            end

            def handle_move_down
              move_cursor { |styler, cursor, width| styler.move_down(cursor, width) }
            end

            # Rendering helpers for the reader-context annotation editor screen.
            include Adapters::Ui::Constants::Ui

            private

            def build_context(surface, bounds)
              RenderContext.new(
                surface: surface,
                bounds: bounds,
                width: bounds.width,
                height: bounds.height,
                reset: Shoko::Shared::Terminal::Ansi::RESET,
                selected_text: @selected_text.to_s.tr("\n", ' '),
                note_text: @note.to_s
              )
            end

            def render_header
              title_width = render_title
              render_hint(title_width)
              render_divider
            end

            def render_title
              title_plain = @is_editing ? 'Editing Annotation' : 'Creating Annotation'
              title = "#{COLOR_TEXT_ACCENT}#{title_plain}#{context.reset}"
              context.surface.write(context.bounds, 1, 2, title)
              Shoko::Shared::Terminal::TextMetrics.visible_length(title_plain)
            end

            def render_hint(title_width)
              hint_plain = '[Ctrl+S] Save • [ESC] Cancel'
              hint_col = hint_column(title_width, hint_plain)
              context.surface.write(context.bounds, 1, hint_col, "#{COLOR_TEXT_DIM}#{hint_plain}#{context.reset}")
            end

            def render_divider
              context.surface.write(context.bounds, 2, 1, COLOR_TEXT_DIM + ('─' * context.width) + context.reset)
            end

            def hint_column(title_width, hint_plain)
              hint_width = Shoko::Shared::Terminal::TextMetrics.visible_length(hint_plain)
              min_hint_col = 2 + title_width + 2
              right_hint_col = context.width - hint_width
              [right_hint_col, min_hint_col].max
            end

            def render_footer
              context.surface.write(
                context.bounds,
                context.height - 1,
                2,
                "#{COLOR_TEXT_DIM}[Type] to edit • [Backspace] delete • [Enter] newline#{context.reset}"
              )
            end

            def move_cursor
              width = @note_inner_width || 40
              styler = Ui::AnnotationMarkup::Styler.new(@note)
              @cursor_pos = yield(styler, @cursor_pos, width)
              record_cursor_activity
            end

            def box_line_text(box, visible_row)
              pair = box.each_visible_line.find { |_line, index| index == visible_row }
              pair ? pair[0].to_s : ''
            end

            # Edit-only: the reader's annotation editor is always opened on an
            # existing annotation, so a save updates its note in place. New
            # annotations are created from a live selection via the notes flow.
            def persist_annotation(service, path)
              return unless @annotation

              service.update(path, @annotation['id'], @note)
            end

            def finalize_save
              @ui.refresh_annotations
              @ui.cleanup_popup_state
              @ui.set_message('Annotation saved!')
              @ui.switch_mode(:read)
            end

            def context
              @render_context
            end

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
