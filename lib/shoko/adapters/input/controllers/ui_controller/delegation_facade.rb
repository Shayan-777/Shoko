# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module UiControllerDelegationFacade
          # === Sidebar delegation ===
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

          def set_sidebar_toc_selected(index)
            @sidebar_controller.set_sidebar_toc_selected(index)
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

          # TOC helpers exposed for external use
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

          # === Annotation overlay delegation ===
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

          def annotation_editor_insert_char(char)
            @annotation_controller.annotation_editor_insert_char(char)
          end

          def annotation_editor_backspace
            @annotation_controller.annotation_editor_backspace
          end

          def annotation_editor_enter
            @annotation_controller.annotation_editor_enter
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

          def annotation_editor_cancel
            @annotation_controller.annotation_editor_cancel
          end

          def annotation_editor_save
            @annotation_controller.annotation_editor_save
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

          # === Dictionary delegation ===
          def handle_lookup_action(action_data)
            @dictionary_controller.handle_lookup_action(action_data)
          end

          def show_dictionary_panel(result, announce: true)
            @dictionary_controller.show_dictionary_panel(result, announce: announce)
          end

          def show_dictionary_popup(result, announce: true)
            @dictionary_controller.show_dictionary_popup(result, announce: announce)
          end

          def close_dictionary(_key = nil)
            @dictionary_controller.close_dictionary
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

          def dictionary_cancel(key = nil)
            @dictionary_controller.dictionary_cancel(key)
          end

          def dictionary_tab(key = nil)
            @dictionary_controller.dictionary_tab(key)
          end

          def dictionary_swap_languages(key = nil)
            @dictionary_controller.dictionary_swap_languages(key)
          end

          def refresh_dictionary_display_mode(terminal_width:, terminal_height:)
            @dictionary_controller.refresh_dictionary_display_mode(
              terminal_width: terminal_width,
              terminal_height: terminal_height
            )
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

          def active_dictionary_component
            @dictionary_controller.active_dictionary_component
          end

          # === In-book search delegation ===
          def open_in_book_search(key = nil)
            @in_book_search_controller.open_in_book_search(key)
          end

          def close_in_book_search(key = nil)
            @in_book_search_controller.close_in_book_search(key)
          end

          def in_book_search_insert_char(char)
            @in_book_search_controller.in_book_search_insert_char(char)
          end

          def in_book_search_backspace(key = nil)
            @in_book_search_controller.in_book_search_backspace(key)
          end

          def in_book_search_confirm(key = nil)
            @in_book_search_controller.in_book_search_confirm(key)
          end

          def in_book_search_cancel(key = nil)
            @in_book_search_controller.in_book_search_cancel(key)
          end

          def in_book_search_up(key = nil)
            @in_book_search_controller.in_book_search_up(key)
          end

          def in_book_search_down(key = nil)
            @in_book_search_controller.in_book_search_down(key)
          end

          def dictionary_visible?
            @dictionary_controller.dictionary_visible?
          end

          def in_book_search_visible?
            @in_book_search_controller.in_book_search_visible?
          end

          def determine_dictionary_display_mode(terminal_width, terminal_height)
            @dictionary_controller.determine_dictionary_display_mode(terminal_width, terminal_height)
          end
        end
      end
    end
  end
end
