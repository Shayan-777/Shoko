# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../terminal/terminal_sanitizer'
require_relative '../ui/box_drawer'
require_relative '../ui/cursor_blink'
require_relative '../ui/annotation_list_input'
require_relative 'annotation_rendering_helpers'

module Shoko
  module Adapters::Output::Ui::Components
    module Screens
      # Simple annotation note editor within the menu (no book load)
      class AnnotationEditScreenComponent < BaseComponent
        include Adapters::Output::Ui::Constants::UI
        include UI::BoxDrawer
        include AnnotationScreenRendering
        include UI::CursorBlink

        attr_reader :edit_state

        def initialize(dependencies = nil)
          super(dependencies)
          @dependencies = dependencies
          @render_context = nil
          @edit_state = AnnotationEditState.new(dependencies)
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

        def preferred_height(_available_height)
          :fill
        end

        # --- Unified editor API (used by Application::Commands) ---
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
            UI::AnnotationListInput.insert_newline(text, cursor)
          end
          record_cursor_activity
        end

        def handle_character(char)
          return unless Shoko::Adapters::Output::Terminal::TerminalSanitizer.printable_char?(char.to_s)

          edit_state.update_from do |text, cursor|
            UI::AnnotationListInput.insert_character(text, cursor, char)
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

        def build_context(surface, bounds)
          annotation = edit_state.selected_annotation
          build_annotation_context(
            surface, bounds,
            AnnotationView.new(annotation || {}),
            resolve_book_label
          )
        end

        def render_header
          title_plain = "📝 Edit Annotation • #{context.book_label}"
          title_width = render_screen_title(context, title_plain)
          render_right_aligned_text(context, '[Ctrl+S] Save • [ESC] Cancel', title_width)
          render_screen_divider(context)
        end

        def render_body
          text_box = build_selected_text_box(context, context.annotation.text, row: 4, height_ratio: 0.25,
                                                                               min_height: 6)
          render_annotation_text_box(text_box, context, color_prefix: COLOR_TEXT_PRIMARY)
          render_note_box(note_box(text_box))
        end

        def render_footer
          footer_text = '[Type] to edit • [Backspace] delete • [Enter] newline'
          context.surface.write(context.bounds, context.height - 1, 2,
                                "#{COLOR_TEXT_DIM}#{footer_text}#{context.reset}")
        end

        def note_box(text_box)
          text_box.next_box(
            total_height: context.height,
            label: 'Note (editable)',
            text: edit_state.text,
            style: :markup
          )
        end

        def render_note_box(box)
          @note_inner_width = box.inner_width
          render_annotation_text_box(box, context, color_prefix: COLOR_TEXT_PRIMARY)
          render_cursor(box)
        end

        def render_cursor(box)
          cursor = edit_state.cursor(box.text)
          row, col = box.cursor_position(cursor)
          visible, glyph = cursor_state
          return unless visible

          context.surface.write(context.bounds, row, col, "#{SELECTION_HIGHLIGHT}#{glyph}#{context.reset}")
        end

        def move_cursor
          edit_state.update_from do |text, cursor|
            width = @note_inner_width || 40
            styler = UI::AnnotationMarkup::Styler.new(text)
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
        rescue StandardError
          nil
        end

        def context
          @render_context
        end
      end
    end
  end
end
