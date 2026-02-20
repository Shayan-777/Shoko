# frozen_string_literal: true

require_relative 'session_outcome'

module Shoko
  module Adapters
    module Ui
        module Sessions
          # Adapter-owned lifecycle for annotations/editor overlays.
          class AnnotationOverlayUiSessionAdapter
            RESCUABLE_ERRORS = [NoMethodError, ArgumentError, TypeError, RuntimeError].freeze

            def initialize(reader_state_reader:, state_writer:, ui_component_factory:, logger: nil)
              @reader_state_reader = reader_state_reader
              @state_writer = state_writer
              @ui_component_factory = ui_component_factory
              @logger = logger
            end

            def annotations_visible?
              overlay = annotations_overlay
              overlay.respond_to?(:visible?) && overlay.visible?
            rescue *RESCUABLE_ERRORS => e
              log_error('annotation.session.annotations_visible?', e)
              false
            end

            def annotation_editor_visible?
              overlay = annotation_editor_overlay
              overlay.respond_to?(:visible?) && overlay.visible?
            rescue *RESCUABLE_ERRORS => e
              log_error('annotation.session.annotation_editor_visible?', e)
              false
            end

            def toggle_annotations
              annotations_visible? ? close_annotations : open_annotations
            end

            def open_annotations
              overlay = @ui_component_factory&.annotations_overlay(@reader_state_reader)
              return failure_outcome(:error, :annotations_overlay_unavailable, 'Annotations overlay component unavailable') unless overlay

              @state_writer.update_reader(annotations_overlay: overlay)
              success_outcome(:opened, :annotations_overlay_opened)
            rescue *RESCUABLE_ERRORS => e
              log_error('annotation.session.open_annotations', e)
              failure_outcome(:error, :annotations_overlay_open_failed, e.message)
            end

            def close_annotations
              annotations_overlay&.hide
              @state_writer.update_reader(annotations_overlay: nil)
              success_outcome(:closed, :annotations_overlay_closed)
            rescue *RESCUABLE_ERRORS => e
              log_error('annotation.session.close_annotations', e)
              failure_outcome(:error, :annotations_overlay_close_failed, e.message)
            end

            def annotations_up
              invoke_annotations_action(:annotations_up, :scroll_up)
            end

            def annotations_down
              invoke_annotations_action(:annotations_down, :scroll_down)
            end

            def annotations_open
              annotation = current_annotation
              return failure_outcome(:ignored, :annotations_open_unavailable, 'No annotation selected') unless annotation

              success_outcome(:handled, :annotations_open_handled, payload: { type: :open, annotation: annotation })
            end

            def annotations_edit
              annotation = current_annotation
              return failure_outcome(:ignored, :annotations_edit_unavailable, 'No annotation selected') unless annotation

              success_outcome(:handled, :annotations_edit_handled, payload: { type: :edit, annotation: annotation })
            end

            def annotations_delete
              annotation = current_annotation
              return failure_outcome(:ignored, :annotations_delete_unavailable, 'No annotation selected') unless annotation

              success_outcome(:handled, :annotations_delete_handled, payload: { type: :delete, annotation: annotation })
            end

            def annotations_cancel
              success_outcome(:handled, :annotations_cancel_handled, payload: { type: :close })
            end

            def set_annotations_selected_index(index)
              overlay = annotations_overlay
              return failure_outcome(:ignored, :annotations_selection_unavailable, 'Annotations overlay selection is unavailable') unless overlay&.respond_to?(:selected_index=)

              overlay.selected_index = index
              success_outcome(:handled, :annotations_selection_updated)
            rescue *RESCUABLE_ERRORS => e
              log_error('annotation.session.set_annotations_selected_index', e)
              failure_outcome(:error, :annotations_selection_update_failed, e.message)
            end

            def open_editor(text:, range:, chapter_index:, annotation: nil)
              overlay = @ui_component_factory&.annotation_editor_overlay(
                selected_text: text,
                range: range,
                chapter_index: chapter_index,
                annotation: annotation
              )
              return failure_outcome(:error, :annotation_editor_unavailable, 'Annotation editor overlay unavailable') unless overlay

              @state_writer.update_reader(annotation_editor_overlay: overlay)
              success_outcome(:opened, :annotation_editor_opened)
            rescue *RESCUABLE_ERRORS => e
              log_error('annotation.session.open_editor', e)
              failure_outcome(:error, :annotation_editor_open_failed, e.message)
            end

            def close_editor
              annotation_editor_overlay&.hide
              @state_writer.update_reader(annotation_editor_overlay: nil)
              success_outcome(:closed, :annotation_editor_closed)
            rescue *RESCUABLE_ERRORS => e
              log_error('annotation.session.close_editor', e)
              failure_outcome(:error, :annotation_editor_close_failed, e.message)
            end

            def editor_insert_char(char)
              invoke_editor_action(:editor_insert_char, :handle_character, char.to_s)
            end

            def editor_backspace
              invoke_editor_action(:editor_backspace, :handle_backspace)
            end

            def editor_enter
              invoke_editor_action(:editor_enter, :handle_enter)
            end

            def editor_move_left
              invoke_editor_action(:editor_move_left, :handle_move_left)
            end

            def editor_move_right
              invoke_editor_action(:editor_move_right, :handle_move_right)
            end

            def editor_move_up
              invoke_editor_action(:editor_move_up, :handle_move_up)
            end

            def editor_move_down
              invoke_editor_action(:editor_move_down, :handle_move_down)
            end

            def editor_cancel
              success_outcome(:handled, :annotation_editor_cancelled, payload: { type: :cancel })
            end

            def editor_save
              invoke_editor_action(:editor_save, :handle_save)
            end

            def handle_editor_click(col, row)
              invoke_editor_action(:editor_click, :handle_click, col, row)
            end

            def editor_context
              overlay = annotation_editor_overlay
              return nil unless overlay

              {
                annotation_id: read_attr(overlay, :annotation_id),
                selected_text: read_attr(overlay, :selected_text),
                note: read_attr(overlay, :note),
                selection_range: read_attr(overlay, :selection_range),
                chapter_index: read_attr(overlay, :chapter_index),
              }
            rescue *RESCUABLE_ERRORS => e
              log_error('annotation.session.editor_context', e)
              nil
            end

            private

            def annotations_overlay
              @reader_state_reader&.annotations_overlay
            rescue *RESCUABLE_ERRORS => e
              log_error('annotation.session.annotations_overlay', e)
              nil
            end

            def annotation_editor_overlay
              @reader_state_reader&.annotation_editor_overlay
            rescue *RESCUABLE_ERRORS => e
              log_error('annotation.session.annotation_editor_overlay', e)
              nil
            end

            def read_attr(target, key)
              target.respond_to?(key) ? target.public_send(key) : nil
            rescue *RESCUABLE_ERRORS => e
              log_error('annotation.session.read_attr', e)
              nil
            end

            def current_annotation
              overlay = annotations_overlay
              return nil unless overlay&.respond_to?(:current_annotation)

              overlay.current_annotation
            rescue *RESCUABLE_ERRORS => e
              log_error('annotation.session.current_annotation', e)
              nil
            end

            def invoke_annotations_action(command, method_name)
              overlay = annotations_overlay
              return failure_outcome(:ignored, "#{command}_unavailable".to_sym, 'Annotations overlay unavailable') unless overlay&.respond_to?(method_name)

              payload = overlay.public_send(method_name)
              success_outcome(:handled, "#{command}_handled".to_sym, payload: payload)
            rescue *RESCUABLE_ERRORS => e
              log_error("annotation.session.#{command}", e)
              failure_outcome(:error, "#{command}_failed".to_sym, e.message)
            end

            def invoke_editor_action(command, method_name, *args)
              overlay = annotation_editor_overlay
              return failure_outcome(:ignored, "#{command}_unavailable".to_sym, 'Annotation editor overlay unavailable') unless overlay&.respond_to?(method_name)

              payload = overlay.public_send(method_name, *args)
              success_outcome(:handled, "#{command}_handled".to_sym, payload: payload)
            rescue *RESCUABLE_ERRORS => e
              log_error("annotation.session.#{command}", e)
              failure_outcome(:error, "#{command}_failed".to_sym, e.message)
            end

            def success_outcome(status, code, payload: nil)
              Shoko::Adapters::Ui::Sessions::SessionOutcome.success(status: status, code: code, payload: payload)
            end

            def failure_outcome(status, code, message, payload: nil)
              Shoko::Adapters::Ui::Sessions::SessionOutcome.failure(
                status: status,
                code: code,
                message: message,
                payload: payload
              )
            end

            def log_error(event, error)
              @logger&.error(event, error: error.class.name, message: error.message)
            end
          end
        end
      end
  end
end
