# frozen_string_literal: true

require_relative 'support/session_outcome_helpers'

module Shoko
  module Adapters
    module Ui
      module Sessions
        # Adapter-owned lifecycle for annotations/editor overlays.
        class AnnotationOverlayUiSessionAdapter
          include Support::SessionOutcomeHelpers

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
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
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
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
            log_error('annotation.session.open_annotations', e)
            failure_outcome(:error, :annotations_overlay_open_failed, e.message)
          end

          def close_annotations
            overlay = annotations_overlay
            overlay&.hide
            @reader_session_mutator.update_reader(annotations_overlay: nil)
            success_outcome(:closed, :annotations_overlay_closed)
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
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
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
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
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
            log_error('annotation.session.close_editor', e)
            failure_outcome(:error, :annotation_editor_close_failed, e.message)
          end

          def annotations_visible?
            overlay = annotations_overlay
            overlay&.visible?
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
            log_error('annotation.session.annotations_visible?', e)
            false
          end

          def annotation_editor_visible?
            overlay = annotation_editor_overlay
            overlay&.visible?
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
            log_error('annotation.session.annotation_editor_visible?', e)
            false
          end

          ANNOTATION_OVERLAY_COMMANDS = {
            annotations_up: :scroll_up.to_proc,
            annotations_down: :scroll_down.to_proc,
          }.freeze

          ANNOTATION_SELECTION_EVENTS = {
            annotations_open: :open,
            annotations_edit: :edit,
            annotations_delete: :delete,
          }.freeze

          def annotations_up
            dispatch_annotations_action(:annotations_up)
          end

          def annotations_down
            dispatch_annotations_action(:annotations_down)
          end

          def annotations_open
            dispatch_annotation_selection(:annotations_open)
          end

          def annotations_edit
            dispatch_annotation_selection(:annotations_edit)
          end

          def annotations_delete
            dispatch_annotation_selection(:annotations_delete)
          end

          def annotations_cancel
            success_outcome(:handled, :annotations_cancel_handled, payload: { type: :close })
          end

          def update_annotations_selected_index(index)
            overlay = annotations_overlay
            unless overlay
              return failure_outcome(
                :ignored,
                :annotations_selection_unavailable,
                'Annotations overlay selection is unavailable'
              )
            end

            overlay.selected_index = index
            success_outcome(:handled, :annotations_selection_updated)
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
            log_error('annotation.session.update_annotations_selected_index', e)
            failure_outcome(:error, :annotations_selection_update_failed, e.message)
          end

          EDITOR_COMMANDS = {
            editor_insert_char: lambda do |overlay, value|
              overlay.handle_character(value)
              nil
            end,
            editor_backspace: lambda do |overlay, *|
              overlay.handle_backspace
              nil
            end,
            editor_enter: lambda do |overlay, *|
              overlay.handle_enter
              nil
            end,
            editor_move_left: lambda do |overlay, *|
              overlay.handle_move_left
              nil
            end,
            editor_move_right: lambda do |overlay, *|
              overlay.handle_move_right
              nil
            end,
            editor_move_up: lambda do |overlay, *|
              overlay.handle_move_up
              nil
            end,
            editor_move_down: lambda do |overlay, *|
              overlay.handle_move_down
              nil
            end,
            editor_cancel: ->(overlay, *) { overlay.handle_cancel },
            editor_save: ->(overlay, *) { overlay.handle_save },
            editor_spellcheck_target: ->(overlay, *) { overlay.spellcheck_target },
            editor_spell_suggestions_state: ->(overlay, *) { overlay.spell_suggestion_state },
            editor_click: ->(overlay, *args) { overlay.handle_click(*args) },
          }.freeze

          def editor_insert_char(char)
            dispatch_editor_action(:editor_insert_char, char.to_s)
          end

          def editor_backspace
            dispatch_editor_action(:editor_backspace)
          end

          def editor_enter
            dispatch_editor_action(:editor_enter)
          end

          def editor_move_left
            dispatch_editor_action(:editor_move_left)
          end

          def editor_move_right
            dispatch_editor_action(:editor_move_right)
          end

          def editor_move_up
            dispatch_editor_action(:editor_move_up)
          end

          def editor_move_down
            dispatch_editor_action(:editor_move_down)
          end

          def editor_cancel
            dispatch_editor_action(:editor_cancel)
          end

          def editor_save
            dispatch_editor_action(:editor_save)
          end

          def editor_spellcheck_target
            dispatch_editor_action(:editor_spellcheck_target)
          end

          def editor_spell_suggestions_state
            dispatch_editor_action(:editor_spell_suggestions_state)
          end

          def editor_show_spell_suggestions(target:, suggestions:, scope_key: nil, scope_label: nil, can_cycle: false)
            overlay = annotation_editor_overlay
            return spell_suggestions_unavailable unless overlay

            overlay.show_spell_suggestions(
              target,
              suggestions,
              **spell_suggestion_options(scope_key, scope_label, can_cycle)
            )
            success_outcome(:handled, :annotation_editor_spell_suggestions_shown)
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
            log_error('annotation.session.editor_show_spell_suggestions', e)
            failure_outcome(:error, :annotation_editor_spell_suggestions_failed, e.message)
          end

          def handle_editor_click(col, row)
            dispatch_editor_action(:editor_click, col, row)
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
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
            log_error('annotation.session.editor_context', e)
            nil
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
              annotation_editor_annotation_id: normalized[:id],
            }
          end

          def symbolize_annotation(annotation)
            annotation.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }
          end

          def annotations_overlay
            @reader_state_reader.annotations_overlay
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
            log_error('annotation.session.annotations_overlay', e)
            nil
          end

          def annotation_editor_overlay
            @reader_state_reader.annotation_editor_overlay
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
            log_error('annotation.session.annotation_editor_overlay', e)
            nil
          end

          def current_rendered_lines
            lines = @rendered_content_reader&.rendered_lines
            lines.is_a?(Hash) ? lines : {}
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
            log_error('annotation.session.current_rendered_lines', e)
            {}
          end

          def current_annotation
            overlay = annotations_overlay
            return nil unless overlay

            overlay.current_annotation
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
            log_error('annotation.session.current_annotation', e)
            nil
          end

          def dispatch_annotations_action(command)
            overlay = annotations_overlay
            unless overlay
              return failure_outcome(:ignored, :"#{command}_unavailable", 'Annotations overlay unavailable')
            end

            payload = ANNOTATION_OVERLAY_COMMANDS.fetch(command).call(overlay)
            success_outcome(:handled, :"#{command}_handled", payload: payload)
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
            log_error("annotation.session.#{command}", e)
            failure_outcome(:error, :"#{command}_failed", e.message)
          end

          def dispatch_annotation_selection(command)
            annotation = current_annotation
            return failure_outcome(:ignored, :"#{command}_unavailable", 'No annotation selected') unless annotation

            event = ANNOTATION_SELECTION_EVENTS.fetch(command)
            success_outcome(:handled, :"#{command}_handled", payload: { type: event, annotation: annotation })
          end

          def spell_suggestions_unavailable
            failure_outcome(
              :ignored,
              :annotation_editor_spell_suggestions_unavailable,
              'Annotation editor overlay unavailable'
            )
          end

          def spell_suggestion_options(scope_key, scope_label, can_cycle)
            {
              scope_key: scope_key,
              scope_label: scope_label,
              can_cycle: can_cycle,
            }
          end

          def dispatch_editor_action(command, *)
            overlay = annotation_editor_overlay
            unless overlay
              return failure_outcome(:ignored, :"#{command}_unavailable", 'Annotation editor overlay unavailable')
            end

            payload = EDITOR_COMMANDS.fetch(command).call(overlay, *)
            success_outcome(:handled, :"#{command}_handled", payload: payload)
          rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
            log_error("annotation.session.#{command}", e)
            failure_outcome(:error, :"#{command}_failed", e.message)
          end
        end
      end
    end
  end
end
