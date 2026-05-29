# frozen_string_literal: true

require_relative 'support/session_outcome_support'
require_relative 'annotation_overlay_ui_session/overlay_access'
require_relative 'annotation_overlay_ui_session/annotation_dispatch'
require_relative 'annotation_overlay_ui_session/editor_dispatch'

module Shoko
  module Adapters
    module Ui
      module Sessions
        # Adapter-owned lifecycle for annotations/editor overlays.
        class AnnotationOverlayUiSessionAdapter
          include Support::SessionOutcomeSupport
          include AnnotationOverlayUiSession::OverlayAccess
          include AnnotationOverlayUiSession::AnnotationDispatch
          include AnnotationOverlayUiSession::EditorDispatch

          def initialize(
            reader_state_reader:,
            reader_session_mutator:,
            ui_component_factory:,
            rendered_content_reader: nil,
            logger: nil
          )
            @reader_state_reader = reader_state_reader
            @reader_session_mutator = reader_session_mutator
            @ui_component_factory = ui_component_factory
            @rendered_content_reader = rendered_content_reader
            @logger = logger
          end

          def refresh_theme(color_mode:)
            overlay = annotation_editor_overlay
            overlay&.update_color_mode(color_mode) if overlay.respond_to?(:update_color_mode)
            success_outcome(:handled, :annotation_theme_refreshed)
          rescue *Support::SessionOutcomeSupport::RESCUABLE_ERRORS => e
            log_error('annotation.session.refresh_theme', e)
            failure_outcome(:error, :annotation_theme_refresh_failed, e.message)
          end

          def toggle_annotations
            annotations_visible? ? close_annotations : open_annotations
          end

          def open_annotations
            overlay = @ui_component_factory.annotations_overlay(@reader_state_reader)
            unless overlay
              return failure_outcome(:error,
                                     :annotations_overlay_unavailable,
                                     'Annotations overlay component unavailable')
            end

            @reader_session_mutator.update_reader(annotations_overlay: overlay)
            success_outcome(:opened, :annotations_overlay_opened)
          rescue *Support::SessionOutcomeSupport::RESCUABLE_ERRORS => e
            log_error('annotation.session.open_annotations', e)
            failure_outcome(:error, :annotations_overlay_open_failed, e.message)
          end

          def close_annotations
            overlay = annotations_overlay
            overlay&.hide
            @reader_session_mutator.update_reader(annotations_overlay: nil)
            success_outcome(:closed, :annotations_overlay_closed)
          rescue *Support::SessionOutcomeSupport::RESCUABLE_ERRORS => e
            log_error('annotation.session.close_annotations', e)
            failure_outcome(:error, :annotations_overlay_close_failed, e.message)
          end

          def open_editor(text:, range:, chapter_index:, annotation: nil)
            seed = editor_seed_attributes(text: text, range: range, chapter_index: chapter_index,
                                          annotation: annotation)
            @reader_session_mutator.update_reader(seed)
            overlay = @ui_component_factory.annotation_editor_overlay(
              reader_state_reader: @reader_state_reader,
              reader_session_mutator: @reader_session_mutator,
              rendered_lines: current_rendered_lines
            )
            unless overlay
              return failure_outcome(:error, :annotation_editor_unavailable, 'Annotation editor overlay unavailable')
            end

            @reader_session_mutator.update_reader(annotation_editor_overlay: overlay)
            success_outcome(:opened, :annotation_editor_opened)
          rescue *Support::SessionOutcomeSupport::RESCUABLE_ERRORS => e
            log_error('annotation.session.open_editor', e)
            failure_outcome(:error, :annotation_editor_open_failed, e.message)
          end

          def close_editor
            overlay = annotation_editor_overlay
            overlay&.hide
            @reader_session_mutator.update_reader(
              annotation_editor_overlay: nil,
              annotation_editor_note: '',
              annotation_editor_cursor: 0,
              annotation_editor_selected_text: '',
              annotation_editor_range: nil,
              annotation_editor_chapter_index: nil,
              annotation_editor_annotation_id: nil
            )
            success_outcome(:closed, :annotation_editor_closed)
          rescue *Support::SessionOutcomeSupport::RESCUABLE_ERRORS => e
            log_error('annotation.session.close_editor', e)
            failure_outcome(:error, :annotation_editor_close_failed, e.message)
          end

          private

          def editor_seed_attributes(text:, range:, chapter_index:, annotation:)
            normalized = annotation.is_a?(Hash) ? symbolize_annotation(annotation) : {}
            note_source = normalized[:note]
            note = (note_source || '').to_s
            {
              annotation_editor_note: note,
              annotation_editor_cursor: note.length,
              annotation_editor_selected_text: (text || '').to_s,
              annotation_editor_range: range,
              annotation_editor_chapter_index: chapter_index,
              annotation_editor_annotation_id: normalized[:id]
            }
          end

          def symbolize_annotation(annotation)
            annotation.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }
          end
        end
      end
    end
  end
end
