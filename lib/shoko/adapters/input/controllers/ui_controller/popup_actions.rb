# frozen_string_literal: true

require_relative '../support/message_notifier'

module Shoko
  module Adapters
    module Input
      module Controllers
        # UI controller actions for popup interactions and overlay cleanup.
        module UiControllerPopupActions
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

          private

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
        end
      end
    end
  end
end
