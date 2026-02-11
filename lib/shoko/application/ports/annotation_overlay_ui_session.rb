# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      # Port for annotations overlay and annotation editor overlay lifecycle.
      module AnnotationOverlayUiSession
        def annotations_visible?
          raise NotImplementedError, "#{self.class} must implement #annotations_visible?"
        end

        def annotation_editor_visible?
          raise NotImplementedError, "#{self.class} must implement #annotation_editor_visible?"
        end

        def toggle_annotations
          raise NotImplementedError, "#{self.class} must implement #toggle_annotations"
        end

        def open_annotations
          raise NotImplementedError, "#{self.class} must implement #open_annotations"
        end

        def close_annotations
          raise NotImplementedError, "#{self.class} must implement #close_annotations"
        end

        def annotations_up
          raise NotImplementedError, "#{self.class} must implement #annotations_up"
        end

        def annotations_down
          raise NotImplementedError, "#{self.class} must implement #annotations_down"
        end

        def annotations_open
          raise NotImplementedError, "#{self.class} must implement #annotations_open"
        end

        def annotations_edit
          raise NotImplementedError, "#{self.class} must implement #annotations_edit"
        end

        def annotations_delete
          raise NotImplementedError, "#{self.class} must implement #annotations_delete"
        end

        def annotations_cancel
          raise NotImplementedError, "#{self.class} must implement #annotations_cancel"
        end

        def set_annotations_selected_index(index)
          raise NotImplementedError, "#{self.class} must implement #set_annotations_selected_index"
        end

        def open_editor(text:, range:, chapter_index:, annotation: nil)
          raise NotImplementedError, "#{self.class} must implement #open_editor"
        end

        def close_editor
          raise NotImplementedError, "#{self.class} must implement #close_editor"
        end

        def editor_insert_char(char)
          raise NotImplementedError, "#{self.class} must implement #editor_insert_char"
        end

        def editor_backspace
          raise NotImplementedError, "#{self.class} must implement #editor_backspace"
        end

        def editor_enter
          raise NotImplementedError, "#{self.class} must implement #editor_enter"
        end

        def editor_move_left
          raise NotImplementedError, "#{self.class} must implement #editor_move_left"
        end

        def editor_move_right
          raise NotImplementedError, "#{self.class} must implement #editor_move_right"
        end

        def editor_move_up
          raise NotImplementedError, "#{self.class} must implement #editor_move_up"
        end

        def editor_move_down
          raise NotImplementedError, "#{self.class} must implement #editor_move_down"
        end

        def editor_cancel
          raise NotImplementedError, "#{self.class} must implement #editor_cancel"
        end

        def editor_save
          raise NotImplementedError, "#{self.class} must implement #editor_save"
        end

        def handle_editor_click(col, row)
          raise NotImplementedError, "#{self.class} must implement #handle_editor_click"
        end

        def editor_context
          raise NotImplementedError, "#{self.class} must implement #editor_context"
        end
      end
    end
  end
end
