# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        # Handles all annotation overlay functionality: annotations overlay and annotation editor
        class AnnotationOverlayController
          # Raised when required dependencies are missing for an annotation action.
          class MissingDependencyError < StandardError; end
          BOUNDARY_ERRORS = [MissingDependencyError, ArgumentError, TypeError, RuntimeError].freeze

          def initialize(reader_state:, state_writer:, ui_component_factory: nil, state_controller: nil,
                         reader_controller: nil, input_controller: nil,
                         annotation_service: nil, notification_service: nil, logger: nil,
                         annotation_overlay_ui_session: nil)
            @reader_state = reader_state
            @state_writer = state_writer
            @ui_component_factory = ui_component_factory
            @state_controller = state_controller
            @reader_controller = reader_controller
            @input_controller = input_controller
            @annotation_service = annotation_service
            @notification_service = notification_service
            @logger = logger
            @annotation_overlay_ui_session = annotation_overlay_ui_session
          end

          def open_annotations
            @annotation_overlay_ui_session&.toggle_annotations
          end

          def open_annotation_editor_overlay(text:, range:, chapter_index:, annotation: nil)
            show_annotation_editor_overlay(text: text,
                                           range: range,
                                           chapter_index: chapter_index,
                                           annotation: annotation)
          end

          def show_annotations_overlay
            raise MissingDependencyError, 'Dependency :annotation_overlay_ui_session not available' unless @annotation_overlay_ui_session

            outcome = @annotation_overlay_ui_session.open_annotations
            return unless session_ok?(outcome)

            set_message('Annotations overlay open (up/down navigate, Enter open, e edit, d delete)', 3)
          rescue *BOUNDARY_ERRORS => e
            @logger&.debug("AnnotationOverlayController.show_annotations_overlay failed: #{e.message}")
            cleanup_annotations_overlay_fallback
          end

          def close_annotations_overlay
            @annotation_overlay_ui_session&.close_annotations
          rescue *BOUNDARY_ERRORS => e
            @logger&.debug("AnnotationOverlayController.close_annotations_overlay failed: #{e.message}")
            cleanup_annotations_overlay_fallback
          end

          def show_annotation_editor_overlay(text:, range:, chapter_index:, annotation: nil)
            message = 'Annotation editor unavailable'
            raise MissingDependencyError, 'Dependency :annotation_overlay_ui_session not available' unless @annotation_overlay_ui_session

            open_outcome = @annotation_overlay_ui_session.open_editor(text: text, range: range, chapter_index: chapter_index,
                                                                      annotation: annotation)
            if session_ok?(open_outcome) && activate_annotation_editor_overlay_session
              message = 'Annotation editor active (Ctrl+S save, Esc cancel)'
            else
              cleanup_annotation_editor_overlay_fallback
            end
          rescue *BOUNDARY_ERRORS => e
            cleanup_annotation_editor_overlay_fallback
            log_dependency_error(:show_annotation_editor_overlay, e)
          ensure
            set_message(message, 3)
          end

          def close_annotation_editor_overlay
            @annotation_overlay_ui_session&.close_editor
            deactivate_annotation_editor_overlay_session
          rescue *BOUNDARY_ERRORS => e
            @logger&.debug("AnnotationOverlayController.close_annotation_editor_overlay failed: #{e.message}")
            cleanup_annotation_editor_overlay_fallback
          end

          def open_annotation_from_overlay(annotation)
            with_normalized_annotation(annotation) do |normalized|
              @state_controller&.jump_to_annotation(normalized)
              close_annotations_overlay
            end
          rescue *BOUNDARY_ERRORS => e
            @logger&.debug("AnnotationOverlayController.open_annotation_from_overlay failed: #{e.message}")
            close_annotations_overlay
          end

          def edit_annotation_from_overlay(annotation)
            with_normalized_annotation(annotation) do |normalized|
              close_annotations_overlay
              show_annotation_editor_overlay(text: normalized[:text],
                                             range: normalized[:range],
                                             chapter_index: normalized[:chapter_index],
                                             annotation: normalized)
            end
          end

          def delete_annotation_from_overlay(annotation)
            with_normalized_annotation(annotation) do |normalized|
              new_index = @state_controller&.delete_annotation_by_id(normalized)

              @annotation_overlay_ui_session&.set_annotations_selected_index(new_index) unless new_index.nil?

              annotations = @reader_state.annotations || []
              close_annotations_overlay if annotations.empty?
              set_message('Annotation deleted', 2)
            end
          rescue *BOUNDARY_ERRORS => e
            @logger&.debug("AnnotationOverlayController.delete_annotation_from_overlay failed: #{e.message}")
            close_annotations_overlay
          end

          def handle_annotation_editor_overlay_event(result)
            result = session_payload(result)
            return unless result

            case result[:type]
            when :save
              save_annotation_from_overlay(result[:note])
            when :cancel
              cancel_annotation_editor_overlay
            end
          end

          def annotations_up
            process_annotations_overlay_event(session_payload(@annotation_overlay_ui_session&.annotations_up))
          end

          def annotations_down
            process_annotations_overlay_event(session_payload(@annotation_overlay_ui_session&.annotations_down))
          end

          def annotations_open
            process_annotations_overlay_event(session_payload(@annotation_overlay_ui_session&.annotations_open))
          end

          def annotations_edit
            process_annotations_overlay_event(session_payload(@annotation_overlay_ui_session&.annotations_edit))
          end

          def annotations_delete
            process_annotations_overlay_event(session_payload(@annotation_overlay_ui_session&.annotations_delete))
          end

          def annotations_cancel
            process_annotations_overlay_event(session_payload(@annotation_overlay_ui_session&.annotations_cancel))
          end

          def annotation_editor_insert_char(char)
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_insert_char(char)))
          end

          def annotation_editor_backspace
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_backspace))
          end

          def annotation_editor_enter
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_enter))
          end

          def annotation_editor_move_left
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_move_left))
          end

          def annotation_editor_move_right
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_move_right))
          end

          def annotation_editor_move_up
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_move_up))
          end

          def annotation_editor_move_down
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_move_down))
          end

          def annotation_editor_cancel
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_cancel))
          end

          def annotation_editor_save
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_save))
          end

          def handle_annotation_editor_overlay_click(col, row)
            session_payload(@annotation_overlay_ui_session&.handle_editor_click(col, row))
          end

          def annotations_overlay_visible?
            @annotation_overlay_ui_session&.annotations_visible? == true
          end

          def annotation_editor_visible?
            @annotation_overlay_ui_session&.annotation_editor_visible? == true
          end

          # Refresh annotations from persistence into state
          def refresh_annotations
            @state_controller&.refresh_annotations
          rescue *BOUNDARY_ERRORS => e
            @logger&.debug("AnnotationOverlayController.refresh_annotations failed: #{e.message}")
          end

          # Provide current book path for modes/components that need persistence context
          def current_book_path
            @reader_state.book_path
          end

          private

          def session_payload(result)
            return result unless session_outcome?(result)

            result.payload
          end

          def session_ok?(result)
            return result.ok if session_outcome?(result)

            !!result
          end

          def session_outcome?(result)
            result.is_a?(Shoko::Shared::Contracts::SessionOutcome)
          end

          def process_annotations_overlay_event(result)
            return :pass unless result

            case result[:type]
            when :selection_change
              index = result[:index]
              @state_writer&.update_sidebar(
                annotations_selected: index,
                sidebar_annotations_selected: index
              )
              :handled
            when :open
              open_annotation_from_overlay(result[:annotation])
              :handled
            when :edit
              edit_annotation_from_overlay(result[:annotation])
              :handled
            when :delete
              delete_annotation_from_overlay(result[:annotation])
              :handled
            when :close
              close_annotations_overlay
              :handled
            else
              :pass
            end
          end

          def process_annotation_editor_event(result)
            return :handled if result.nil?

            handle_annotation_editor_overlay_event(result)
            :handled
          end

          def save_annotation_from_overlay(note)
            svc = @annotation_service
            path = current_book_path
            context = @annotation_overlay_ui_session&.editor_context
            unless svc && path && context
              cancel_annotation_editor_overlay
              return
            end

            begin
              if context && context[:annotation_id]
                svc.update(path, context[:annotation_id], note)
                set_message('Annotation updated', 2)
              else
                svc.add(path, context[:selected_text], note, context[:selection_range], context[:chapter_index], nil)
                set_message('Annotation saved!', 2)
              end
              refresh_annotations
            rescue *BOUNDARY_ERRORS => e
              set_message("Save failed: #{e.message}", 3)
            ensure
              close_annotation_editor_overlay
              @state_writer.clear_selection
            end
          end

          def cancel_annotation_editor_overlay
            close_annotation_editor_overlay
            set_message('Annotation cancelled', 2)
            @state_writer.clear_selection
          end

          def activate_annotation_editor_overlay_session
            raise MissingDependencyError, 'Dependency :input_controller not available' unless @input_controller

            @input_controller.enter_modal_mode(:annotation_editor)
            true
          rescue MissingDependencyError => e
            log_dependency_error(:activate_annotation_editor_overlay_session, e)
            false
          end

          def deactivate_annotation_editor_overlay_session
            @input_controller&.exit_modal_mode(:annotation_editor)
          end

          def cleanup_annotations_overlay_fallback
            @annotation_overlay_ui_session&.close_annotations || @state_writer.update_reader(annotations_overlay: nil)
          rescue *BOUNDARY_ERRORS => e
            @logger&.debug("AnnotationOverlayController.cleanup_annotations_overlay_fallback failed: #{e.message}")
            nil
          end

          def cleanup_annotation_editor_overlay_fallback
            @annotation_overlay_ui_session&.close_editor || @state_writer.update_reader(annotation_editor_overlay: nil)
            deactivate_annotation_editor_overlay_session
          rescue *BOUNDARY_ERRORS
            raise
          end

          def normalize_annotation(annotation)
            return nil unless annotation.is_a?(Hash)

            annotation.transform_keys do |key|
              key.is_a?(String) ? key.to_sym : key
            end
          end

          def with_normalized_annotation(annotation)
            normalized = normalize_annotation(annotation)
            return unless normalized

            yield normalized
          end

          def set_message(text, duration = 2)
            if @notification_service
              @notification_service.set_message(text, duration)
            else
              @state_writer.update_reader(message: text)
            end
          rescue *BOUNDARY_ERRORS
            @state_writer.update_reader(message: text)
          end

          def log_dependency_error(context, error)
            @logger&.error('Annotation editor activation failed', context: context, error: error.message)
          rescue *BOUNDARY_ERRORS
            raise
          end
        end
      end
    end
  end
end
