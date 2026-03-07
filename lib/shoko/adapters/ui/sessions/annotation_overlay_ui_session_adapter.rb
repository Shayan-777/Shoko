# frozen_string_literal: true

require_relative '../../../shared/contracts/session_outcome'

module Shoko
  module Adapters
    module Ui
      module Sessions
        # Adapter-owned lifecycle for annotations/editor overlays.
        class AnnotationOverlayUiSessionAdapter
          RESCUABLE_ERRORS = [ArgumentError, TypeError, RuntimeError].freeze

          def initialize(reader_state_reader:, state_writer:, ui_component_factory:, rendered_content_reader: nil,
                         logger: nil)
            @reader_state_reader = reader_state_reader
            @state_writer = state_writer
            @ui_component_factory = ui_component_factory
            @rendered_content_reader = rendered_content_reader
            @logger = logger
          end

          def annotations_visible?
            overlay = annotations_overlay
            overlay&.visible?
          rescue *RESCUABLE_ERRORS => e
            log_error('annotation.session.annotations_visible?', e)
            false
          end

          def annotation_editor_visible?
            overlay = annotation_editor_overlay
            overlay&.visible?
          rescue *RESCUABLE_ERRORS => e
            log_error('annotation.session.annotation_editor_visible?', e)
            false
          end

          def refresh_theme(color_mode:)
            overlay = annotation_editor_overlay
            overlay&.update_color_mode(color_mode) if overlay.respond_to?(:update_color_mode)
            success_outcome(:handled, :annotation_theme_refreshed)
          rescue *RESCUABLE_ERRORS => e
            log_error('annotation.session.refresh_theme', e)
            failure_outcome(:error, :annotation_theme_refresh_failed, e.message)
          end

          def toggle_annotations
            annotations_visible? ? close_annotations : open_annotations
          end

          def open_annotations
            overlay = @ui_component_factory.annotations_overlay(@reader_state_reader)
            unless overlay
              return failure_outcome(:error, :annotations_overlay_unavailable,
                                     'Annotations overlay component unavailable')
            end

            @state_writer.update_reader(annotations_overlay: overlay)
            success_outcome(:opened, :annotations_overlay_opened)
          rescue *RESCUABLE_ERRORS => e
            log_error('annotation.session.open_annotations', e)
            failure_outcome(:error, :annotations_overlay_open_failed, e.message)
          end

          def close_annotations
            overlay = annotations_overlay
            overlay&.hide
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
            unless annotation
              return failure_outcome(:ignored, :annotations_delete_unavailable, 'No annotation selected')
            end

            success_outcome(:handled, :annotations_delete_handled, payload: { type: :delete, annotation: annotation })
          end

          def annotations_cancel
            success_outcome(:handled, :annotations_cancel_handled, payload: { type: :close })
          end

          def set_annotations_selected_index(index)
            overlay = annotations_overlay
            unless overlay
              return failure_outcome(:ignored, :annotations_selection_unavailable,
                                     'Annotations overlay selection is unavailable')
            end

            overlay.selected_index = index
            success_outcome(:handled, :annotations_selection_updated)
          rescue *RESCUABLE_ERRORS => e
            log_error('annotation.session.set_annotations_selected_index', e)
            failure_outcome(:error, :annotations_selection_update_failed, e.message)
          end

          def open_editor(text:, range:, chapter_index:, annotation: nil)
            overlay = @ui_component_factory.annotation_editor_overlay(
              selected_text: text,
              range: range,
              chapter_index: chapter_index,
              annotation: annotation,
              rendered_lines: current_rendered_lines
            )
            unless overlay
              return failure_outcome(:error, :annotation_editor_unavailable, 'Annotation editor overlay unavailable')
            end

            @state_writer.update_reader(annotation_editor_overlay: overlay)
            success_outcome(:opened, :annotation_editor_opened)
          rescue *RESCUABLE_ERRORS => e
            log_error('annotation.session.open_editor', e)
            failure_outcome(:error, :annotation_editor_open_failed, e.message)
          end

          def close_editor
            overlay = annotation_editor_overlay
            overlay&.hide
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
            invoke_editor_action(:editor_cancel, :handle_cancel)
          end

          def editor_save
            invoke_editor_action(:editor_save, :handle_save)
          end

          def editor_spellcheck_target
            invoke_editor_action(:editor_spellcheck_target, :spellcheck_target)
          end

          def editor_spell_suggestions_state
            invoke_editor_action(:editor_spell_suggestions_state, :spell_suggestion_state)
          end

          def editor_show_spell_suggestions(target:, suggestions:, scope_key: nil, scope_label: nil, can_cycle: false)
            overlay = annotation_editor_overlay
            unless overlay
              return failure_outcome(:ignored, :annotation_editor_spell_suggestions_unavailable,
                                     'Annotation editor overlay unavailable')
            end

            overlay.show_spell_suggestions(
              target,
              suggestions,
              scope_key: scope_key,
              scope_label: scope_label,
              can_cycle: can_cycle
            )
            success_outcome(:handled, :annotation_editor_spell_suggestions_shown)
          rescue *RESCUABLE_ERRORS => e
            log_error('annotation.session.editor_show_spell_suggestions', e)
            failure_outcome(:error, :annotation_editor_spell_suggestions_failed, e.message)
          end

          def handle_editor_click(col, row)
            invoke_editor_action(:editor_click, :handle_click, col, row)
          end

          def editor_context
            overlay = annotation_editor_overlay
            return nil unless overlay

            {
              annotation_id: overlay.annotation_id,
              selected_text: overlay.selected_text,
              note: overlay.note,
              selection_range: overlay.selection_range,
              chapter_index: overlay.chapter_index,
            }
          rescue *RESCUABLE_ERRORS => e
            log_error('annotation.session.editor_context', e)
            nil
          end

          private

          def annotations_overlay
            @reader_state_reader.annotations_overlay
          rescue *RESCUABLE_ERRORS => e
            log_error('annotation.session.annotations_overlay', e)
            nil
          end

          def annotation_editor_overlay
            @reader_state_reader.annotation_editor_overlay
          rescue *RESCUABLE_ERRORS => e
            log_error('annotation.session.annotation_editor_overlay', e)
            nil
          end

          def current_rendered_lines
            lines = @rendered_content_reader&.rendered_lines
            lines.is_a?(Hash) ? lines : {}
          rescue *RESCUABLE_ERRORS => e
            log_error('annotation.session.current_rendered_lines', e)
            {}
          end

          def current_annotation
            overlay = annotations_overlay
            return nil unless overlay

            overlay.current_annotation
          rescue *RESCUABLE_ERRORS => e
            log_error('annotation.session.current_annotation', e)
            nil
          end

          def invoke_annotations_action(command, method_name)
            overlay = annotations_overlay
            unless overlay
              return failure_outcome(:ignored, "#{command}_unavailable".to_sym, 'Annotations overlay unavailable')
            end

            payload = invoke_annotations_method(overlay, method_name)
            success_outcome(:handled, "#{command}_handled".to_sym, payload: payload)
          rescue *RESCUABLE_ERRORS => e
            log_error("annotation.session.#{command}", e)
            failure_outcome(:error, "#{command}_failed".to_sym, e.message)
          end

          def invoke_editor_action(command, method_name, *)
            overlay = annotation_editor_overlay
            unless overlay
              return failure_outcome(:ignored, "#{command}_unavailable".to_sym, 'Annotation editor overlay unavailable')
            end

            payload = invoke_editor_method(overlay, method_name, *)
            success_outcome(:handled, "#{command}_handled".to_sym, payload: payload)
          rescue *RESCUABLE_ERRORS => e
            log_error("annotation.session.#{command}", e)
            failure_outcome(:error, "#{command}_failed".to_sym, e.message)
          end

          def invoke_annotations_method(overlay, method_name)
            case method_name
            when :scroll_up then overlay.scroll_up
            when :scroll_down then overlay.scroll_down
            else
              raise ArgumentError, "Unsupported annotations overlay method: #{method_name}"
            end
          end

          def invoke_editor_method(overlay, method_name, *)
            case method_name
            when :handle_character
              overlay.handle_character(*)
              nil
            when :handle_backspace
              overlay.handle_backspace
              nil
            when :handle_enter
              overlay.handle_enter
              nil
            when :handle_move_left
              overlay.handle_move_left
              nil
            when :handle_move_right
              overlay.handle_move_right
              nil
            when :handle_move_up
              overlay.handle_move_up
              nil
            when :handle_move_down
              overlay.handle_move_down
              nil
            when :handle_cancel then overlay.handle_cancel
            when :handle_save then overlay.handle_save
            when :spellcheck_target then overlay.spellcheck_target
            when :spell_suggestion_state then overlay.spell_suggestion_state
            when :handle_click then overlay.handle_click(*)
            else
              raise ArgumentError, "Unsupported annotation editor overlay method: #{method_name}"
            end
          end

          def success_outcome(status, code, payload: nil)
            Shoko::Shared::Contracts::SessionOutcome.success(status: status, code: code, payload: payload)
          end

          def failure_outcome(status, code, message, payload: nil)
            Shoko::Shared::Contracts::SessionOutcome.failure(
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
