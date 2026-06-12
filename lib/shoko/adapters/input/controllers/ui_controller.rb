# frozen_string_literal: true

require_relative 'dependencies/ui_controller_dependencies'
require_relative 'support/message_notifier'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Coordinates all UI-related functionality by delegating to specialized controllers.
        class UIController
          # Raised when required dependencies are missing for a UI action.
          class MissingDependencyError < StandardError; end

          Dependencies = Shoko::Adapters::Input::Controllers::Dependencies::UiControllerDependencies::Bundle

          # Builds the annotation editor screen component for annotation editor mode.
          class AnnotationEditorMode
            def initialize(controller, annotation_service, component_factory)
              @controller = controller
              @annotation_service = annotation_service
              @component_factory = component_factory
            end

            def build_component(**)
              @component_factory.annotation_editor_screen(
                controller: @controller,
                annotation_service: @annotation_service,
                **
              )
            end
          end

          attr_reader :current_mode

          def initialize(deps:)
            dependencies = deps.validate!
            assign_state_dependencies(dependencies.state)
            assign_controller_dependencies(dependencies.controllers)
            assign_service_dependencies(dependencies.services)
            @current_mode = nil
          end

          # Theme refresh is best-effort: a failure leaves the previous theme
          # in place and must never break the render or input path.
          def refresh_theme(theme_context: nil, theme: nil)
            context = resolve_theme_context(theme_context: theme_context, theme: theme)
            propagate_theme_context(context)
            context
          # resilient-boundary
          rescue StandardError => e
            record_theme_refresh_error(e)
          end

          # Mode switching
          def switch_mode(mode, **)
            annotation_editor_mode =
              if mode == :annotation_editor
                UIController::AnnotationEditorMode.new(self, @annotation_service, @ui_component_factory)
              end
            close_annotations_overlay unless annotation_editor_mode
            close_annotation_editor_overlay unless annotation_editor_mode
            @reader_session_mutator.update_reader(mode: mode)

            @current_mode = annotation_editor_mode&.build_component(**)
          end

          # === UI config methods ===
          def show_help(_key = nil)
            switch_mode(:help)
          end

          def toggle_view_mode(_key = nil)
            @reader_session_mutator.toggle_view_mode
          end

          def increase_line_spacing(_key = nil)
            modes = %i[compact normal relaxed]
            current = modes.index(@config_reader.line_spacing) || 1
            return unless current < 2

            @reader_session_mutator.update_config(line_spacing: modes[current + 1])
            @reader_session_mutator.update_reader(last_width: 0)
          end

          def decrease_line_spacing(_key = nil)
            modes = %i[compact normal relaxed]
            current = modes.index(@config_reader.line_spacing) || 1
            return unless current.positive?

            @reader_session_mutator.update_config(line_spacing: modes[current - 1])
            @reader_session_mutator.update_reader(last_width: 0)
          end

          def toggle_page_numbering_mode(_key = nil)
            current_mode = @config_reader.page_numbering_mode
            new_mode = current_mode == :absolute ? :dynamic : :absolute
            @reader_session_mutator.update_config(page_numbering_mode: new_mode)
            set_message("Page numbering: #{new_mode}")
          end

          include Shoko::Adapters::Input::Controllers::Support::MessageNotifier

          # === Popup handling ===
          def handle_popup_action(action_data)
            action_type = action_data.is_a?(Hash) ? action_data[:action] : action_data

            case action_type
            when :create_annotation, 'Create Annotation'
              # Route through the notes use case (re-enters the use-case layer via the
              # input controller), mirroring "Look Up"/"Translate": the selected text
              # anchors a new note opened straight in the bar-anchored compose editor.
              @input_controller.dispatch_reader_intent(:open_notes, action_data)
              return # Don't cleanup popup state - the notes panel owns its lifecycle
            when :copy_to_clipboard, 'Copy to Clipboard'
              handle_copy_to_clipboard_action(action_data)
            when :lookup, 'Look Up'
              # Route the lookup through the dictionary use case (re-enters the
              # use-case layer via the input controller) so the use case owns the
              # dictionary result write, rather than calling the controller directly.
              @input_controller.dispatch_reader_intent(:open_dictionary, action_data)
              return # Don't cleanup popup state - dictionary overlay handles its own cleanup
            when :translate, 'Translate'
              # Route through the translator use case (re-enters the use-case layer
              # via the input controller), mirroring "Look Up": the selected text
              # pre-fills the bar-anchored translator card, which owns its lifecycle.
              @input_controller.dispatch_reader_intent(:open_translator, action_data)
              return # Don't cleanup popup state - translator overlay handles its own cleanup
            end

            cleanup_popup_state
          end

          def cleanup_popup_state(skip_editor: false)
            @reader_session_mutator.update_reader(popup_menu: nil)
            @reader_session_mutator.clear_selection
            close_in_book_search
            close_annotations_overlay
            close_annotation_editor_overlay unless skip_editor
            begin
              @reader_controller&.clear_active_selection
            rescue Shoko::Error
              # Best-effort; ignore if not available
            end
          end

          include Shoko::Adapters::Input::Controllers::Support::MessageNotifier

          def open_annotations
            @annotation_controller.open_annotations
          end

          def open_annotation_editor_overlay(text:, range:, chapter_index:, annotation: nil)
            @annotation_controller.open_annotation_editor_overlay(
              text: text,
              range: range,
              chapter_index: chapter_index,
              annotation: annotation
            )
          end

          def show_annotations_overlay
            @annotation_controller.show_annotations_overlay
          end

          def close_annotations_overlay
            @annotation_controller.close_annotations_overlay
          end

          def show_annotation_editor_overlay(text:, range:, chapter_index:, annotation: nil)
            @annotation_controller.show_annotation_editor_overlay(
              text: text,
              range: range,
              chapter_index: chapter_index,
              annotation: annotation
            )
          end

          def close_annotation_editor_overlay
            @annotation_controller.close_annotation_editor_overlay
          end

          def annotations_overlay_visible?
            @annotation_controller.annotations_overlay_visible?
          end

          def annotation_editor_visible?
            @annotation_controller.annotation_editor_visible?
          end

          def open_annotation_from_overlay(annotation)
            @annotation_controller.open_annotation_from_overlay(annotation)
          end

          def edit_annotation_from_overlay(annotation)
            @annotation_controller.edit_annotation_from_overlay(annotation)
          end

          def delete_annotation_from_overlay(annotation)
            @annotation_controller.delete_annotation_from_overlay(annotation)
          end

          def annotations_up
            @annotation_controller.annotations_up
          end

          def annotations_down
            @annotation_controller.annotations_down
          end

          def annotations_open
            @annotation_controller.annotations_open
          end

          def annotations_edit
            @annotation_controller.annotations_edit
          end

          def annotations_delete
            @annotation_controller.annotations_delete
          end

          def annotations_cancel
            @annotation_controller.annotations_cancel
          end

          def annotation_editor_move_left
            @annotation_controller.annotation_editor_move_left
          end

          def annotation_editor_move_right
            @annotation_controller.annotation_editor_move_right
          end

          def annotation_editor_move_up
            @annotation_controller.annotation_editor_move_up
          end

          def annotation_editor_move_down
            @annotation_controller.annotation_editor_move_down
          end

          def annotation_editor_spellcheck
            @annotation_controller.annotation_editor_spellcheck
          end

          def annotation_editor_enter
            @annotation_controller.annotation_editor_enter
          end

          def handle_annotation_editor_overlay_click(col, row)
            @annotation_controller.handle_annotation_editor_overlay_click(col, row)
          end

          def handle_annotation_editor_overlay_event(result)
            @annotation_controller.handle_annotation_editor_overlay_event(result)
          end

          def refresh_annotations
            @annotation_controller.refresh_annotations
          end

          def current_book_path
            @annotation_controller.current_book_path
          end

          def open_dictionary_lookup(payload = nil)
            @dictionary_controller.open_dictionary_lookup(payload)
          end

          def submit_dictionary_lookup(_key = nil)
            @dictionary_controller.submit_dictionary_lookup
          end

          def close_dictionary_lookup(_key = nil)
            @dictionary_controller.close_dictionary_lookup
          end

          # Kept for InputRouter's Esc intercept (dictionary_cancel?).
          def close_dictionary(_key = nil)
            @dictionary_controller.close_dictionary_lookup
          end

          def dictionary_insert_char(char)
            @dictionary_controller.dictionary_insert_char(char)
          end

          def dictionary_backspace(key = nil)
            @dictionary_controller.dictionary_backspace(key)
          end

          def dictionary_confirm(key = nil)
            @dictionary_controller.dictionary_confirm(key)
          end

          def dictionary_tab(key = nil)
            @dictionary_controller.dictionary_tab(key)
          end

          def dictionary_swap_languages(key = nil)
            @dictionary_controller.dictionary_swap_languages(key)
          end

          def dictionary_scroll_up(key = nil)
            @dictionary_controller.dictionary_scroll_up(key)
          end

          def dictionary_scroll_down(key = nil)
            @dictionary_controller.dictionary_scroll_down(key)
          end

          def dictionary_toggle_fuzzy(key = nil)
            @dictionary_controller.dictionary_toggle_fuzzy(key)
          end

          def dictionary_cycle_result(key = nil)
            @dictionary_controller.dictionary_cycle_result(key)
          end

          def dictionary_cycle_pair(key = nil)
            @dictionary_controller.dictionary_cycle_pair(key)
          end

          def dictionary_visible?
            @dictionary_controller.dictionary_visible?
          end

          def open_toc_lookup(key = nil)
            @toc_controller.open_toc_lookup(key)
          end

          def close_toc_lookup(key = nil)
            @toc_controller.close_toc_lookup(key)
          end

          def edit_toc_filter(edit_op)
            @toc_controller.edit_toc_filter(edit_op)
          end

          def move_toc_selection(delta)
            @toc_controller.move_toc_selection(delta)
          end

          def activate_toc_selection(key = nil)
            @toc_controller.activate_toc_selection(key)
          end

          def toc_lookup_visible?
            @toc_controller.toc_lookup_visible?
          end

          def open_translator(payload = nil)
            @translator_controller.open_translator(payload)
          end

          def close_translator(key = nil)
            @translator_controller.close_translator(key)
          end

          # Kept for InputRouter's Esc intercept (translator_cancel?).
          def close_translator_lookup(key = nil)
            @translator_controller.close_translator(key)
          end

          def edit_translator(edit_op)
            @translator_controller.edit_translator(edit_op)
          end

          def translator_confirm(key = nil)
            @translator_controller.translator_confirm(key)
          end

          def translator_cursor_move(direction)
            @translator_controller.translator_cursor_move(direction)
          end

          def translator_cycle_picker(key = nil)
            @translator_controller.translator_cycle_picker(key)
          end

          def translator_swap_languages(key = nil)
            @translator_controller.translator_swap_languages(key)
          end

          def translator_visible?
            @translator_controller.translator_visible?
          end

          def open_notes_lookup(payload = nil)
            @notes_controller.open_notes_lookup(payload)
          end

          def close_notes_lookup(_key = nil)
            @notes_controller.close_notes_lookup
          end

          # Kept for InputRouter's Esc intercept (notes_cancel?).
          def close_notes(_key = nil)
            @notes_controller.close_notes_lookup
          end

          def move_notes_selection(delta)
            @notes_controller.move_notes_selection(delta)
          end

          def confirm_notes_selection(_key = nil)
            @notes_controller.confirm_notes_selection
          end

          def edit_selected_note(_key = nil)
            @notes_controller.edit_selected_note
          end

          def new_note(_key = nil)
            @notes_controller.new_note
          end

          def delete_selected_note(_key = nil)
            @notes_controller.delete_selected_note
          end

          def edit_note_input(edit_op)
            @notes_controller.edit_note_input(edit_op)
          end

          def move_note_cursor(direction)
            @notes_controller.move_note_cursor(direction)
          end

          def notes_visible?
            @notes_controller.notes_lookup_visible?
          end

          def open_in_book_search(key = nil)
            @in_book_search_controller.open_in_book_search(key)
          end

          def close_in_book_search(key = nil)
            @in_book_search_controller.close_in_book_search(key)
          end

          def submit_in_book_search(key = nil)
            @in_book_search_controller.submit_in_book_search(key)
          end

          def open_search_result(result)
            @in_book_search_controller.open_search_result(result)
          end

          def in_book_search_visible?
            @in_book_search_controller.in_book_search_visible?
          end

          private

          def record_theme_refresh_error(error)
            @logger&.debug('ui_controller.refresh_theme_failed', error: error.class.name, message: error.message)
            nil
          end

          def resolve_theme_context(theme_context:, theme:)
            return theme_context if theme_context

            @ui_component_factory&.apply_theme(theme_id: theme || @config_reader&.theme)
          end

          def propagate_theme_context(context)
            @dictionary_controller&.refresh_theme(theme_context: context)
            @annotation_controller&.refresh_theme(theme_context: context)
            @in_book_search_controller&.refresh_theme(theme_context: context)
            @toc_controller&.refresh_theme(theme_context: context)
            @translator_controller&.refresh_theme(theme_context: context)
          end

          def assign_state_dependencies(deps)
            @reader_state = deps.reader_state
            @config_reader = deps.config_reader
            @reader_session_mutator = deps.reader_session_mutator
            @ui_state = deps.ui_state
            @selection_service = deps.selection_service
            @rendered_content_reader = deps.rendered_content_reader
          end

          def assign_controller_dependencies(deps)
            @dictionary_controller = deps.dictionary_controller
            @annotation_controller = deps.annotation_controller
            @in_book_search_controller = deps.in_book_search_controller
            @toc_controller = deps.toc_controller
            @translator_controller = deps.translator_controller
            @notes_controller = deps.notes_controller
            @input_controller = deps.input_controller
            @reader_controller = deps.reader_controller
          end

          def assign_service_dependencies(deps)
            @notification_service = deps.notification_service
            @clipboard_service = deps.clipboard_service
            @ui_component_factory = deps.ui_component_factory
            @annotation_service = deps.annotation_service
            @logger = deps.logger
          end

          def handle_copy_to_clipboard_action(_action_data)
            clipboard_service = @clipboard_service
            selection = @reader_state.selection
            selected_text = extract_selected_text_from_selection(selection)

            if clipboard_service.available? && selected_text && !selected_text.strip.empty?
              success = clipboard_service.copy_with_feedback(selected_text) do |msg|
                set_message(msg)
              end
              set_message(' Failed to copy to clipboard') unless success
            else
              set_message(' Copy to clipboard not available')
            end
            switch_mode(:read)
          end

          def extract_selected_text_from_selection(selection_range)
            return nil unless @selection_service && @rendered_content_reader

            rendered_lines = @rendered_content_reader.rendered_lines
            @selection_service.extract_text(selection_range, rendered_lines)
          end
        end
      end
    end
  end
end
