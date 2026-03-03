# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../../shared/terminal/text_sanitizer'
require_relative '../ui/cursor_blink'
require_relative '../ui/annotation_list_input'
require_relative '../ui/annotation_markup'
require_relative '../ui/text_utils'
require_relative '../menu_design/frame_renderer'
require_relative '../menu_design/layout'
require_relative '../menu_design/status_renderer'
require_relative '../../../../shared/terminal/ansi'
require_relative 'annotation_rendering_helpers'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Note editor for selected annotation from menu flows.
          class AnnotationEditScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::TextUtils
            include AnnotationScreenRendering
            include Ui::CursorBlink

            GUTTER_WIDTH = 4

            attr_reader :edit_state

            def initialize(dependencies = nil, menu_visual_profile: nil)
              super(dependencies)
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @edit_state = AnnotationEditState.new(dependencies)
              @editor_text_width = nil
              @editor_scroll_top = 0
              initialize_cursor_blink
            end

            def do_render(surface, bounds)
              annotation = edit_state.selected_annotation
              view = AnnotationView.new(annotation || {})

              frame = MenuDesign::FrameRenderer.new(surface, bounds)
              frame.render_title(title: 'Edit Annotation', hint: 'Ctrl-S save  Esc cancel  Arrows move')
              frame.render_divider

              unless annotation
                render_empty(surface, bounds)
                frame.render_footer(text: 'No annotation selected for editing')
                return
              end

              layout = compute_layout(bounds)
              render_status_row(surface, bounds, layout, view)
              render_quote_context(surface, bounds, layout, view)
              render_editor(surface, bounds, layout)

              frame.render_footer(text: footer_text(layout))
            end

            def preferred_height(_available_height)
              :fill
            end

            # --- Unified editor API (used by Application::UseCases::Commands) ---
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
                Ui::AnnotationListInput.insert_newline(text, cursor)
              end
              record_cursor_activity
            end

            def handle_character(char)
              return unless Shoko::Shared::Terminal::TextSanitizer.printable_char?(char.to_s)

              edit_state.update_from do |text, cursor|
                Ui::AnnotationListInput.insert_character(text, cursor, char)
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

            private

            def render_empty(surface, bounds)
              MenuDesign::StatusRenderer.new(surface, bounds).render_empty(
                row: bounds.height / 2,
                indent: 2,
                message: 'Select an annotation first, then press E to edit its note.',
                color: COLOR_TEXT_DIM
              )
            end

            def render_status_row(surface, bounds, layout, annotation)
              left = "Book • #{resolve_book_label}"
              right_parts = [
                "Ch #{annotation.chapter_index || '—'}",
                annotation.page_meta && "Page #{annotation.page_meta}",
                "#{edit_state.text.length} chars"
              ].compact

              MenuDesign::StatusRenderer.new(surface, bounds).render_status(
                row: layout[:status_row],
                indent: layout[:content_indent],
                left: truncate_text(left, [layout[:content_width] - 10, 8].max),
                right: right_parts.join('  •  '),
                width: layout[:content_width],
                left_color: COLOR_TEXT_DIM,
                right_color: COLOR_TEXT_DIM
              )
            end

            def render_quote_context(surface, bounds, layout, annotation)
              heading_style = "#{Shoko::Shared::Terminal::Ansi::BOLD}#{COLOR_TEXT_ACCENT}"
              reset = Shoko::Shared::Terminal::Ansi::RESET
              surface.write(bounds, layout[:quote_heading_row], layout[:content_indent],
                            "#{heading_style}Selected Text Context#{reset}")
              surface.write(bounds, layout[:quote_divider_row], layout[:content_indent],
                            "#{COLOR_TEXT_DIM}#{'─' * layout[:content_width]}#{reset}")

              quote = annotation.text.to_s.strip
              quote = 'No selected text.' if quote.empty?
              lines = wrap_text(safe_text(quote), [layout[:content_width] - 2, 8].max)
              visible = lines.first(layout[:quote_lines_visible])

              visible.each_with_index do |line, index|
                row = layout[:quote_start_row] + index
                content = truncate_text("│ #{line}", layout[:content_width])
                surface.write(bounds, row, layout[:content_indent], pad_right(content, layout[:content_width]))
              end
            end

            def render_editor(surface, bounds, layout)
              heading_style = "#{Shoko::Shared::Terminal::Ansi::BOLD}#{COLOR_TEXT_ACCENT}"
              reset = Shoko::Shared::Terminal::Ansi::RESET

              surface.write(bounds, layout[:editor_heading_row], layout[:content_indent],
                            "#{heading_style}Note Editor#{reset}")
              surface.write(bounds, layout[:editor_divider_row], layout[:content_indent],
                            "#{COLOR_TEXT_DIM}#{'─' * layout[:content_width]}#{reset}")

              text = edit_state.text.to_s
              @editor_text_width = [layout[:content_width] - GUTTER_WIDTH - 1, 8].max
              styler = Ui::AnnotationMarkup::Styler.new(text)
              lines = styler.render_lines(@editor_text_width)

              cursor_index = edit_state.cursor(text)
              cursor_line, cursor_col = styler.cursor_position(cursor_index, @editor_text_width)
              @editor_scroll_top = compute_scroll_top(cursor_line, layout[:editor_height])

              visible = lines[@editor_scroll_top, layout[:editor_height]] || []
              layout[:editor_height].times do |index|
                row = layout[:editor_start_row] + index
                absolute_line = @editor_scroll_top + index
                line_text = visible[index].to_s
                line_text = "#{line_text}#{Ui::AnnotationMarkup::STYLE_RESET}"

                gutter = pad_left((absolute_line + 1).to_s, GUTTER_WIDTH - 1)
                padded = pad_right(line_text, @editor_text_width)
                surface.write(
                  bounds,
                  row,
                  layout[:content_indent],
                  "#{COLOR_TEXT_DIM}#{gutter} #{reset}#{COLOR_TEXT_PRIMARY}#{padded}#{reset}"
                )
              end

              render_cursor(surface, bounds, layout, cursor_line, cursor_col)
            end

            def render_cursor(surface, bounds, layout, cursor_line, cursor_col)
              visible, glyph = cursor_state
              return unless visible

              visible_line = cursor_line - @editor_scroll_top
              return if visible_line.negative? || visible_line >= layout[:editor_height]

              clamped_col = cursor_col.clamp(0, [@editor_text_width - 1, 0].max)
              row = layout[:editor_start_row] + visible_line
              col = layout[:content_indent] + GUTTER_WIDTH + clamped_col
              surface.write(bounds, row, col, "#{SELECTION_HIGHLIGHT}#{glyph}#{Shoko::Shared::Terminal::Ansi::RESET}")
            end

            def compute_scroll_top(cursor_line, editor_height)
              return 0 if editor_height <= 0
              return 0 if cursor_line < editor_height

              cursor_line - editor_height + 1
            end

            def compute_layout(bounds)
              content_width = MenuDesign::Layout.centered_content_width(bounds, preferred: 110, min: 58,
                                                                        horizontal_padding: 8)
              indent = MenuDesign::Layout.centered_indent(bounds, content_width)

              quote_heading = 4
              quote_divider = 5
              quote_start = 6
              quote_visible = bounds.height >= 30 ? 4 : 3

              editor_heading = quote_start + quote_visible + 1
              editor_divider = editor_heading + 1
              editor_start = editor_divider + 1
              editor_bottom = bounds.height - 2
              editor_height = [editor_bottom - editor_start + 1, 3].max

              {
                status_row: 3,
                content_indent: indent,
                content_width: content_width,
                quote_heading_row: quote_heading,
                quote_divider_row: quote_divider,
                quote_start_row: quote_start,
                quote_lines_visible: quote_visible,
                editor_heading_row: editor_heading,
                editor_divider_row: editor_divider,
                editor_start_row: editor_start,
                editor_height: editor_height,
              }
            end

            def footer_text(layout)
              text = edit_state.text.to_s
              cursor = edit_state.cursor(text)
              width = @editor_text_width || [layout[:content_width] - GUTTER_WIDTH - 1, 8].max
              line, col = Ui::AnnotationMarkup::Styler.new(text).cursor_position(cursor, width)
              "Editing note • line #{line + 1}, col #{col + 1} • #{text.length} chars"
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
              service = @dependencies&.annotation_service
              return unless service

              path, ann_id, text = payload.values_at(:path, :ann_id, :text)
              service.update(path, ann_id, text)
              edit_state.refresh_annotations(service)
            rescue Shoko::Error
              nil
            end

            def safe_text(text)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(
                text,
                preserve_newlines: false,
                preserve_tabs: false
              )
            end
          end
        end
      end
    end
  end
end
