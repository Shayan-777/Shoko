# frozen_string_literal: true

require_relative 'dependencies/ui_controller_dependencies'
require_relative 'support/message_notifier'
require_relative '../../../shared/key_definitions'

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

          def refresh_theme(theme_context: nil, theme: nil)
            context = resolve_theme_context(theme_context: theme_context, theme: theme)
            propagate_theme_context(context)
            context
          # resilient-boundary
          rescue Shoko::Error => e
            @logger&.debug('ui_controller.refresh_theme_failed', error: e.class.name, message: e.message)
            nil
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
              handle_create_annotation_action(action_data)
            when :copy_to_clipboard, 'Copy to Clipboard'
              handle_copy_to_clipboard_action(action_data)
            when :lookup, 'Look Up'
              # Route the lookup through the dictionary use case (re-enters the
              # use-case layer via the input controller) so the use case owns the
              # dictionary result write, rather than calling the controller directly.
              @input_controller.dispatch_reader_intent(:open_dictionary, action_data)
              return # Don't cleanup popup state - dictionary overlay handles its own cleanup
            when :translate, 'Translate'
              handle_translate_action(action_data)
              return # Translation popup manages its own cleanup lifecycle
            end

            skip_editor = %i[create_annotation].include?(action_type) || action_type == 'Create Annotation'
            cleanup_popup_state(skip_editor: skip_editor)
          end

          def cleanup_popup_state(skip_editor: false)
            @reader_session_mutator.update_reader(popup_menu: nil)
            close_translation_popup
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

          def handle_translate_action(action_data)
            selected_text = translation_text_for(action_data)
            return reject_translation('No text selected for translation') if selected_text.nil? || selected_text.empty?
            return reject_translation('Translator service is unavailable') unless @translation_service

            result = @translation_service.translate(selected_text, source_lang: 'auto', target_lang: 'en')
            show_translation_popup(result)
          end

          def close_translation_popup
            popup = current_translation_popup
            popup&.hide
            @reader_session_mutator.update_reader(translation_popup: nil)
            @reader_session_mutator.clear_selection
            :handled
          rescue Shoko::Error => e
            @logger&.debug('ui_controller.translation_popup_close_failed', error: e.class.name, message: e.message)
            pass_input_result
          end

          def translation_popup_visible?
            current_translation_popup&.visible? == true
          rescue Shoko::Error => e
            @logger&.debug('ui_controller.translation_popup_visibility_failed', error: e.class.name, message: e.message)
            visibility_fallback?
          end

          def handle_translation_popup_input(keys)
            return :pass unless translation_popup_visible?

            Array(keys).each do |key|
              return close_translation_popup if cancel_key?(key)

              scroll_translation_popup(-1) if up_key?(key)
              scroll_translation_popup(1) if down_key?(key)
            end

            :handled
          end

          def refresh_translation_popup_theme(theme_context:)
            color_mode = theme_context&.color_mode
            popup = current_translation_popup
            popup.update_color_mode(color_mode) if popup.respond_to?(:update_color_mode)
          rescue Shoko::Error => e
            @logger&.debug(
              'ui_controller.translation_popup_theme_refresh_failed',
              error: e.class.name,
              message: e.message
            )
            ignored_refresh
          end


          def open_toc
            @sidebar_controller.open_toc
          end

          def open_bookmarks
            @sidebar_controller.open_bookmarks
          end

          def open_annotations_tab
            @sidebar_controller.open_annotations_tab
          end

          def activate_sidebar_tab(tab)
            @sidebar_controller.activate_sidebar_tab(tab)
          end

          def handle_sidebar_toc_click(index)
            @sidebar_controller.handle_sidebar_toc_click(index)
          end

          def select_sidebar_toc_index(index)
            @sidebar_controller.select_sidebar_toc_index(index)
          end

          def sidebar_down
            @sidebar_controller.sidebar_down
          end

          def sidebar_up
            @sidebar_controller.sidebar_up
          end

          def sidebar_select
            @sidebar_controller.sidebar_select
          end

          def sidebar_toggle_toc
            @sidebar_controller.sidebar_toggle_toc
          end

          def sidebar_visible?
            @sidebar_controller.sidebar_visible?
          end

          def close_sidebar_with_restore(tab)
            @sidebar_controller.close_sidebar_with_restore(tab)
          end

          def toc_entries_for(doc)
            @sidebar_controller.toc_entries_for(doc)
          end

          def toc_collapsed_for(entries, raw = nil)
            @sidebar_controller.toc_collapsed_for(entries, raw)
          end

          def toc_visible_indices(entries, collapsed)
            @sidebar_controller.toc_visible_indices(entries, collapsed)
          end

          def toc_entry_has_children?(entries, index)
            @sidebar_controller.toc_entry_has_children?(entries, index)
          end


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

          def resolve_theme_context(theme_context:, theme:)
            return theme_context if theme_context

            @ui_component_factory&.apply_theme(theme_id: theme || @config_reader&.theme)
          end

          def propagate_theme_context(context)
            @dictionary_controller&.refresh_theme(theme_context: context)
            @annotation_controller&.refresh_theme(theme_context: context)
            @in_book_search_controller&.refresh_theme(theme_context: context)
            refresh_translation_popup_theme(theme_context: context)
          end

          def assign_state_dependencies(deps)
            @reader_state = deps.reader_state
            @config_reader = deps.config_reader
            @reader_session_mutator = deps.reader_session_mutator
            @sidebar_state = deps.sidebar_state
            @ui_state = deps.ui_state
            @selection_service = deps.selection_service
            @rendered_content_reader = deps.rendered_content_reader
          end

          def assign_controller_dependencies(deps)
            @sidebar_controller = deps.sidebar_controller
            @dictionary_controller = deps.dictionary_controller
            @annotation_controller = deps.annotation_controller
            @in_book_search_controller = deps.in_book_search_controller
            @input_controller = deps.input_controller
            @reader_controller = deps.reader_controller
          end

          def assign_service_dependencies(deps)
            @notification_service = deps.notification_service
            @clipboard_service = deps.clipboard_service
            @ui_component_factory = deps.ui_component_factory
            @annotation_service = deps.annotation_service
            @translation_service = deps.translation_service
            @logger = deps.logger
          end


          def handle_create_annotation_action(action_data)
            selection_range = if action_data.is_a?(Hash)
                                action_data[:data][:selection_range]
                              else
                                @reader_state.selection
                              end
            selected_text = extract_selected_text_from_selection(selection_range)
            close_annotations_overlay
            show_annotation_editor_overlay(text: selected_text,
                                           range: selection_range,
                                           chapter_index: @reader_state.current_chapter)
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


          def show_translation_popup(result)
            popup = current_translation_popup || @ui_component_factory&.translation_popup
            return reject_translation('Translator popup is unavailable') unless popup

            popup.show(result)
            @reader_session_mutator.update_reader(translation_popup: popup, popup_menu: nil)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('ui_controller.translation_popup_failed', error: e.message)
            reject_translation(e.message)
          end

          def translation_text_for(action_data)
            selection_range = translation_selection_range(action_data)
            return nil unless selection_range && @selection_service && @rendered_content_reader

            text = @selection_service.extract_text(selection_range, @rendered_content_reader.rendered_lines)
            cleaned = text.to_s.strip.gsub(/\s+/, ' ')
            cleaned.empty? ? nil : cleaned
          end

          def translation_selection_range(action_data)
            return @reader_state.selection unless action_data.is_a?(Hash)

            action_data.dig(:data, :selection_range) || @reader_state.selection
          end

          def current_translation_popup
            return nil unless @reader_state.respond_to?(:translation_popup)

            @reader_state.translation_popup
          end

          def scroll_translation_popup(delta)
            popup = current_translation_popup
            return unless popup

            delta.negative? ? popup.scroll_up : popup.scroll_down
          end

          def reject_translation(message)
            set_message(message)
            @reader_session_mutator.update_reader(popup_menu: nil)
            :pass
          end

          def cancel_key?(key)
            keys = Shoko::Shared::KeyDefinitions::ACTIONS
            keys[:cancel].include?(key) || keys[:quit].include?(key)
          end

          def up_key?(key)
            Shoko::Shared::KeyDefinitions::NAVIGATION[:up].include?(key)
          end

          def down_key?(key)
            Shoko::Shared::KeyDefinitions::NAVIGATION[:down].include?(key)
          end

          def pass_input_result
            :pass
          end

          def visibility_fallback?
            false
          end

          def ignored_refresh
            nil
          end

        end
      end
    end
  end
end
