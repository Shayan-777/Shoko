# frozen_string_literal: true

require_relative '../../../../application/ports/outbound/application_exit_control'
require_relative '../../../../application/ports/outbound/reader_annotation_editor_control'
require_relative '../../../../application/ports/outbound/reader_dictionary_control'
require_relative '../../../../application/ports/outbound/reader_overlay_control'
require_relative '../../../../application/ports/outbound/reader_lifecycle_control'
require_relative '../../../../application/ports/outbound/reader_popup_control'
require_relative '../../../../application/ports/outbound/reader_search_control'
require_relative '../../../../application/ports/outbound/reader_toc_control'
require_relative '../../../../application/ports/outbound/reader_translator_control'
require_relative '../../../../application/ports/outbound/reader_notes_control'
require_relative '../../../../shared/key_definitions'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Aggregates the reader action ports implemented against the reader controller.
          class IntentRuntimeBridge
            include Shoko::Application::Ports::Outbound::ApplicationExitControl
            include Shoko::Application::Ports::Outbound::ReaderAnnotationEditorControl
            include Shoko::Application::Ports::Outbound::ReaderDictionaryControl
            include Shoko::Application::Ports::Outbound::ReaderOverlayControl
            include Shoko::Application::Ports::Outbound::ReaderLifecycleControl
            include Shoko::Application::Ports::Outbound::ReaderPopupControl
            include Shoko::Application::Ports::Outbound::ReaderSearchControl
            include Shoko::Application::Ports::Outbound::ReaderTocControl
            include Shoko::Application::Ports::Outbound::ReaderTranslatorControl
            include Shoko::Application::Ports::Outbound::ReaderNotesControl

            def initialize(reader_controller:)
              @reader_controller = reader_controller
            end


            def move_annotation_cursor(direction:)
              case direction
              when :left then controller.annotation_editor_move_left
              when :right then controller.annotation_editor_move_right
              when :up then controller.annotation_editor_move_up
              when :down then controller.annotation_editor_move_down
              end
            end

            def spellcheck_annotation
              controller.annotation_editor_spellcheck
            end

            def confirm_annotation_editor
              controller.annotation_editor_enter
            end

            def close_annotation_editor
              controller.close_annotation_editor_overlay
            end


            def open_dictionary_lookup(payload = nil)
              controller.open_dictionary_lookup(payload)
            end

            def close_dictionary_lookup
              controller.close_dictionary_lookup
            end

            def submit_dictionary_lookup
              controller.submit_dictionary_lookup
            end

            def cycle_dictionary_result
              controller.dictionary_cycle_result
            end

            def cycle_dictionary_pair
              controller.dictionary_cycle_pair
            end

            def swap_dictionary_languages
              controller.dictionary_swap_languages
            end

            def toggle_dictionary_fuzzy_matching
              controller.dictionary_toggle_fuzzy
            end

            def edit_dictionary_setup(edit_op)
              case edit_op.operation
              when :insert    then controller.dictionary_insert_char(edit_op.text.to_s)
              when :backspace then controller.dictionary_backspace
              end
            end

            def confirm_dictionary_setup
              controller.dictionary_confirm
            end

            def move_dictionary_setup(delta:)
              delta.negative? ? controller.dictionary_scroll_up : controller.dictionary_scroll_down
            end

            def apply_dictionary_setup
              controller.dictionary_tab
            end


            def move_popup_selection(delta:)
              key = if delta.negative?
                      Shoko::Shared::KeyDefinitions::NAVIGATION[:up].first
                    else
                      Shoko::Shared::KeyDefinitions::NAVIGATION[:down].first
                    end
              controller.handle_popup_navigation(key)
            end

            def confirm_popup
              controller.handle_popup_action_key(Shoko::Shared::KeyDefinitions::ACTIONS[:confirm].first)
            end

            def cancel_popup
              controller.handle_popup_cancel(Shoko::Shared::KeyDefinitions::ACTIONS[:cancel].first)
            end


            def show_annotations_overlay
              controller.open_annotations
            end

            def rebuild_pagination
              controller.rebuild_pagination
            end

            def clear_pagination_cache
              controller.invalidate_pagination_cache
            end

            def return_to_menu
              controller.quit_to_menu
            end

            def quit_application
              controller.quit_application
            end


            def open_search_session
              controller.open_in_book_search
            end

            def close_search_session
              controller.close_in_book_search
            end

            def submit_search_session
              controller.submit_in_book_search
            end

            def open_search_result(result)
              controller.open_search_result(result)
            end


            def open_toc_lookup
              controller.open_toc_lookup
            end

            def close_toc_lookup
              controller.close_toc_lookup
            end

            def edit_toc_filter(edit_op)
              controller.edit_toc_filter(edit_op)
            end

            def move_toc_selection(delta)
              controller.move_toc_selection(delta)
            end

            def activate_toc_selection
              controller.activate_toc_selection
            end

            def open_translator_session(payload = nil)
              controller.open_translator(payload)
            end

            def close_translator_session
              controller.close_translator
            end

            def edit_translator_input(edit_op)
              controller.edit_translator(edit_op)
            end

            def confirm_translator
              controller.translator_confirm
            end

            def move_translator_cursor(direction)
              controller.translator_cursor_move(direction)
            end

            def cycle_translator_picker
              controller.translator_cycle_picker
            end

            def swap_translator_languages
              controller.translator_swap_languages
            end


            def open_notes_lookup(payload = nil)
              controller.open_notes_lookup(payload)
            end

            def close_notes_lookup
              controller.close_notes_lookup
            end

            def move_notes_selection(delta)
              controller.move_notes_selection(delta)
            end

            def confirm_notes_selection
              controller.confirm_notes_selection
            end

            def edit_selected_note
              controller.edit_selected_note
            end

            def new_note
              controller.new_note
            end

            def delete_selected_note
              controller.delete_selected_note
            end

            def edit_note_input(edit_op)
              controller.edit_note_input(edit_op)
            end

            def move_note_cursor(direction)
              controller.move_note_cursor(direction)
            end


            def show_toc_sidebar
              controller.open_toc
            end

            def show_bookmarks_sidebar
              controller.open_bookmarks
            end

            def show_annotations_sidebar
              controller.open_annotations_tab
            end

            def toggle_sidebar_visibility
              controller.sidebar_toggle_toc
            end

            def move_sidebar_selection(delta:)
              delta.negative? ? controller.sidebar_up : controller.sidebar_down
            end

            def activate_sidebar_selection
              controller.sidebar_select
            end


            private

            def controller
              @reader_controller
            end

          end
        end
      end
    end
  end
end
