# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../terminal/terminal_sanitizer'
require_relative '../ui/box_drawer'
require_relative 'annotation_rendering_helpers'

module Shoko
  module Adapters::Output::Ui::Components
    module Screens
      # Simple annotation note editor within the menu (no book load)
      class AnnotationEditScreenComponent < BaseComponent
        include Adapters::Output::Ui::Constants::UI
        include UI::BoxDrawer
        include AnnotationScreenRendering

        attr_reader :edit_state

        def initialize(state, dependencies = nil)
          super(dependencies)
          @state = state
          @dependencies = dependencies
          @render_context = nil
          @edit_state = AnnotationEditState.new(@state)
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

        def handle_backspace
          edit_state.update_from do |text, cursor|
            next nil if cursor <= 0

            prev_cursor = cursor - 1
            [text[0...prev_cursor] + text[(prev_cursor + 1)..].to_s, prev_cursor]
          end
        end

        def handle_enter
          edit_state.update_from do |text, cursor|
            new_text = text.dup
            new_text.insert(cursor, "\n")
            [new_text, cursor + 1]
          end
        end

        def handle_character(char)
          return unless Shoko::Adapters::Output::Terminal::TerminalSanitizer.printable_char?(char.to_s)

          edit_state.update_from do |text, cursor|
            new_text = text.dup
            new_text.insert(cursor, char)
            [new_text, cursor + 1]
          end
        end

        private

        def build_context(surface, bounds)
          annotation = edit_state.selected_annotation
          build_annotation_context(
            surface, bounds,
            AnnotationView.new(annotation || {}),
            resolve_book_label(@state)
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
          text_box.next_box(total_height: context.height, label: 'Note (editable)', text: edit_state.text)
        end

        def render_note_box(box)
          render_annotation_text_box(box, context, color_prefix: COLOR_TEXT_PRIMARY)
          render_cursor(box)
        end

        def render_cursor(box)
          cursor = edit_state.cursor(box.text)
          row, col = box.cursor_position(cursor)
          context.surface.write(context.bounds, row, col, "#{SELECTION_HIGHLIGHT}_#{context.reset}")
        end

        def persist_annotation(payload)
          service = @dependencies&.resolve(:annotation_service)
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
