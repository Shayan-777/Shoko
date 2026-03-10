# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module UiControllerDelegation
          module Annotation
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

            def annotation_editor_spellcheck
              @annotation_controller.annotation_editor_spellcheck
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
          end
        end
      end
    end
  end
end
