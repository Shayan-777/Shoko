# frozen_string_literal: true

require_relative '../base_component'
require 'shoko/shared/terminal/text_sanitizer'
require_relative '../ui/cursor_blink'
require 'shoko/shared/annotation_list_input'
require_relative '../ui/annotation_markup'
require_relative '../ui/text_utils'
require_relative '../menu_design/canvas_frame'
require_relative '../menu_design/view_accents'
require_relative '../status_bar/palette'
require 'shoko/shared/terminal/ansi'
require_relative 'annotation_screen_rendering'
require_relative 'annotation_view'
require_relative 'annotation_edit_state'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Note editor for a selected annotation: the quoted passage as muted
          # context up top, and the note in a raised compose well beneath it —
          # the in-book notes compose treatment given the whole canvas. Line
          # numbers ride a dim gutter inside the well; the caret is the same
          # blinking thin stripe the other editors use.
          class AnnotationEditScreenComponent < BaseComponent
            include Ui::TextUtils
            include AnnotationScreenRendering
            include Ui::CursorBlink

            Palette = StatusBar::Palette

            GUTTER_WIDTH = 4
            QUOTE_ROWS = 3
            WELL_PAD = 1

            attr_reader :edit_state

            def initialize(menu_state_reader: nil, menu_session_mutator: nil, annotation_service: nil,
                           menu_visual_profile: nil)
              super()
              @menu_state_reader = menu_state_reader
              @annotation_service = annotation_service
              @menu_visual_profile = menu_visual_profile
              @edit_state = AnnotationEditState.new(menu_state_reader: menu_state_reader,
                                                    menu_session_mutator: menu_session_mutator)
              @editor_text_width = nil
              @editor_scroll_top = 0
              initialize_cursor_blink
            end

            def do_render(surface, bounds)
              frame = MenuDesign::CanvasFrame.new(surface, bounds)
              frame.paint
              annotation = edit_state.selected_annotation
              view = AnnotationView.new(annotation || {})
              frame.render_rule(title: 'Edit Annotation', accent: accent, meta: rule_meta(view, annotation))
              return render_empty(frame) unless annotation

              layout = compute_layout(frame)
              render_quote_context(frame, view, layout)
              render_editor(surface, bounds, frame, layout)
              frame.render_hint(hint_text(layout))
            end

            def preferred_height(_available_height)
              :fill
            end

            # --- Unified editor API ---
            def save_annotation
              payload = edit_state.annotation_update_payload
              return unless payload

              persist_annotation(payload)
              edit_state.return_to_annotations_list
            end

            def cancel_annotation
              edit_state.return_to_annotations_list
            end

            def handle_backspace
              edit_state.update_from do |text, cursor|
                next nil if cursor <= 0

                prev_cursor = cursor - 1
                [text[0...prev_cursor] + text[(prev_cursor + 1)..].to_s, prev_cursor]
              end
              record_cursor_activity
            end

            def handle_enter
              edit_state.update_from do |text, cursor|
                Shoko::Shared::AnnotationListInput.insert_newline(text, cursor)
              end
              record_cursor_activity
            end

            def handle_character(char)
              return unless Shoko::Shared::Terminal::TextSanitizer.printable_char?(char.to_s)

              edit_state.update_from do |text, cursor|
                Shoko::Shared::AnnotationListInput.insert_character(text, cursor, char)
              end
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

            EditorRenderContext = Data.define(:surface, :bounds, :frame, :layout, :lines, :cursor_state)

            private

            def accent
              MenuDesign::ViewAccents.for(:annotations)
            end

            def rule_meta(view, annotation)
              return '' unless annotation

              parts = [compact_book_label]
              parts << "Ch #{view.chapter_index}" if view.chapter_index
              parts << "#{edit_state.text.length} chars"
              parts.join(' · ')
            end

            def compact_book_label
              Shoko::Shared::Terminal::TextSanitizer.sanitize(
                resolve_book_label.to_s, preserve_newlines: false, preserve_tabs: false
              )
            end

            def render_empty(frame)
              row = frame.body_top + [frame.body_height / 2, 0].max - 1
              frame.write_line(row, [['Select an annotation first, then press E to edit its note.',
                                      Palette::LANDING_DIM_FG]])
              frame.render_hint('ESC back')
            end

            def hint_text(layout)
              text = edit_state.text.to_s
              cursor = edit_state.cursor(text)
              width = @editor_text_width || [layout[:well_width] - GUTTER_WIDTH - 2, 8].max
              line, col = Ui::AnnotationMarkup::Styler.new(text).cursor_position(cursor, width)
              "CTRL-S save · ESC cancel · line #{line + 1}, col #{col + 1}"
            end

            def compute_layout(frame)
              editor_top = frame.body_top + QUOTE_ROWS + 2
              {
                quote_top: frame.body_top,
                well_top: editor_top,
                well_height: [frame.body_bottom - editor_top + 1, 3].max,
                well_width: frame.content_width,
              }
            end

            def render_quote_context(frame, view, layout)
              frame.write_line(layout[:quote_top], [['SELECTED TEXT', Palette::LANDING_DIM_FG]])
              lines = visible_quote_lines(view, frame)
              lines.each_with_index do |line, index|
                lead = index.zero? ? '❝ ' : '  '
                frame.write_line(layout[:quote_top] + 1 + index,
                                 [[lead, Palette::LANDING_DIM_FG], [line, Palette::NOTES_EXCERPT_FG]])
              end
            end

            def visible_quote_lines(view, frame)
              quote = view.text.to_s.strip
              quote = 'No selected text.' if quote.empty?
              wrap_words(safe_text(quote), [frame.content_width - 4, 8].max).first(QUOTE_ROWS)
            end

            # ----- the compose well -----

            def render_editor(surface, bounds, frame, layout)
              paint_well(surface, bounds, frame, layout)
              render_editor_lines(
                EditorRenderContext.new(
                  surface: surface, bounds: bounds, frame: frame, layout: layout,
                  lines: prepared_editor_lines(layout),
                  cursor_state: prepared_cursor_state(layout)
                )
              )
            end

            def paint_well(surface, bounds, frame, layout)
              blank = "#{Palette::RESET}#{Palette::NOTES_FIELD_BG}#{' ' * layout[:well_width]}#{Palette::RESET}"
              layout[:well_height].times do |offset|
                surface.write(bounds, layout[:well_top] + offset, frame.content_x, blank)
              end
            end

            def editor_text_width(layout)
              [layout[:well_width] - GUTTER_WIDTH - (WELL_PAD * 2) - 1, 8].max
            end

            def prepared_editor_text(layout)
              @editor_text_width = editor_text_width(layout)
              edit_state.text.to_s
            end

            def prepared_editor_lines(layout)
              text = prepared_editor_text(layout)
              Ui::AnnotationMarkup::Styler.new(text).render_lines(@editor_text_width)
            end

            def prepared_cursor_state(layout)
              text = prepared_editor_text(layout)
              styler = Ui::AnnotationMarkup::Styler.new(text)
              editor_cursor_state(styler, text, layout)
            end

            def editor_cursor_state(styler, text, layout)
              cursor_index = edit_state.cursor(text)
              cursor_line, cursor_col = styler.cursor_position(cursor_index, @editor_text_width)
              @editor_scroll_top = compute_scroll_top(cursor_line, layout[:well_height])
              {
                line: cursor_line,
                col: cursor_col,
                visible_line: cursor_line - @editor_scroll_top,
              }
            end

            def compute_scroll_top(cursor_line, editor_height)
              return 0 if editor_height <= 0
              return 0 if cursor_line < editor_height

              cursor_line - editor_height + 1
            end

            def visible_editor_lines(lines, layout)
              visible = lines[@editor_scroll_top, layout[:well_height]] || []
              Array.new(layout[:well_height]) { |index| visible[index].to_s }
            end

            def render_editor_lines(context)
              visible_editor_lines(context.lines, context.layout).each_with_index do |line_text, index|
                render_editor_line(context, index, line_text)
              end
            end

            def render_editor_line(context, index, line_text)
              absolute_line = @editor_scroll_top + index
              row = context.layout[:well_top] + index
              gutter = pad_left((absolute_line + 1).to_s, GUTTER_WIDTH - 1)
              content = editor_line_text(line_text, index, context.cursor_state)
              context.surface.write(
                context.bounds, row, context.frame.content_x + WELL_PAD,
                editor_line_shell(gutter, pad_right(content, @editor_text_width))
              )
            end

            def editor_line_text(line_text, index, cursor_state)
              display = "#{line_text}#{Ui::AnnotationMarkup::STYLE_RESET}"
              return display unless index == cursor_state[:visible_line]

              inline_cursor_text(
                display,
                cursor_state[:col],
                width: @editor_text_width,
                style_prefix: Palette::NOTES_CARET_FG,
                restore_prefix: Palette::NOTES_INPUT_FG
              )
            end

            # Every span rides the well surface; embedded full resets are
            # re-based so markup styling can never drop the well background.
            def editor_line_shell(gutter, padded)
              base = "#{Palette::RESET}#{Palette::NOTES_FIELD_BG}"
              body = padded.gsub(Shoko::Shared::Terminal::Ansi::RESET, "#{base}#{Palette::NOTES_INPUT_FG}")
              "#{base}#{Palette::LANDING_DIM_FG}#{gutter} #{base}#{Palette::NOTES_INPUT_FG}#{body}#{Palette::RESET}"
            end

            def move_cursor
              edit_state.update_from do |text, cursor|
                width = @editor_text_width || 40
                styler = Ui::AnnotationMarkup::Styler.new(text)
                new_cursor = yield(styler, cursor, width)
                [text, new_cursor]
              end
              record_cursor_activity
            end

            def persist_annotation(payload)
              service = @annotation_service
              return unless service

              path, ann_id, text = payload.values_at(:path, :ann_id, :text)
              service.update(path, ann_id, text)
              edit_state.refresh_annotations(service)
            end

            def safe_text(text)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(text, preserve_newlines: false, preserve_tabs: false)
            end
          end
        end
      end
    end
  end
end
