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
require_relative 'annotation_edit_screen_component/render_support'

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
            include AnnotationEditScreenRenderSupport

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
                "#{edit_state.text.length} chars",
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

            def compute_scroll_top(cursor_line, editor_height)
              return 0 if editor_height <= 0
              return 0 if cursor_line < editor_height

              cursor_line - editor_height + 1
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
