# frozen_string_literal: true

require_relative '../support/message_notifier'
require_relative '../support/session_outcome_support'

module Shoko
  module Adapters
    module Input
      module Controllers
        class AnnotationOverlayController
          # Handles annotation editor modal lifecycle and persistence actions.
          class EditorWorkflow
            include Shoko::Adapters::Input::Controllers::Support::MessageNotifier
            include Shoko::Adapters::Input::Controllers::Support::SessionOutcomeSupport

            BOUNDARY_ERRORS = [ArgumentError, TypeError, RuntimeError].freeze

            def initialize(reader_state:, reader_session_mutator:, state_controller:, annotation_service:, input_controller:,
                           ui_session:, notification_service:, logger:, spellcheck_coordinator:)
              @reader_state = reader_state
              @reader_session_mutator = reader_session_mutator
              @state_controller = state_controller
              @annotation_service = annotation_service
              @input_controller = input_controller
              @ui_session = ui_session
              @notification_service = notification_service
              @logger = logger
              @spellcheck_coordinator = spellcheck_coordinator
            end

            def open(text:, range:, chapter_index:, annotation: nil)
              message = 'Annotation editor unavailable'
              raise ArgumentError, 'Dependency :annotation_overlay_ui_session not available' unless @ui_session

              open_outcome = @ui_session.open_editor(
                text: text,
                range: range,
                chapter_index: chapter_index,
                annotation: annotation
              )
              if session_ok?(open_outcome) && activate_session
                message = 'Annotation editor active (Ctrl+S save, Esc cancel)'
              else
                cleanup_fallback
              end
            rescue *BOUNDARY_ERRORS => e
              cleanup_fallback
              log_dependency_error(:show_annotation_editor_overlay, e)
            ensure
              set_message(message, 3)
            end

            def close
              @ui_session&.close_editor
              deactivate_session
            rescue *BOUNDARY_ERRORS => e
              @logger&.debug("AnnotationOverlayController.close_annotation_editor_overlay failed: #{e.message}")
              cleanup_fallback
            end

            def handle_event(result)
              payload = normalize_payload(session_payload(result))
              return unless payload.is_a?(Hash)

              case payload[:type]
              when :save
                save(payload[:note])
              when :cancel
                cancel
              end
            end

            def process_event(result)
              payload = session_payload(result)
              return :handled if payload.nil? || !payload.is_a?(Hash)

              handle_event(payload)
              :handled
            end

            def spellcheck
              @spellcheck_coordinator.run
            end

            def handle_click(col, row)
              session_payload(@ui_session&.handle_editor_click(col, row))
            end

            def visible?
              @ui_session&.annotation_editor_visible? == true
            end

            def refresh_theme(theme_context:)
              color_mode = theme_context&.color_mode
              @ui_session&.refresh_theme(color_mode: color_mode)
            end

            private

            def save(note)
              context = @ui_session&.editor_context
              unless @annotation_service && current_book_path && context
                cancel
                return
              end

              begin
                if context[:annotation_id]
                  @annotation_service.update(current_book_path, context[:annotation_id], note)
                  set_message('Annotation updated', 2)
                else
                  @annotation_service.add(
                    current_book_path,
                    context[:selected_text],
                    note,
                    context[:selection_range],
                    context[:chapter_index],
                    nil
                  )
                  set_message('Annotation saved!', 2)
                end
                refresh_annotations
              rescue *BOUNDARY_ERRORS => e
                set_message("Save failed: #{e.message}", 3)
              ensure
                close
                @reader_session_mutator.clear_selection
              end
            end

            def cancel
              close
              set_message('Annotation cancelled', 2)
              @reader_session_mutator.clear_selection
            end

            def current_book_path
              @reader_state.book_path
            end

            def refresh_annotations
              @state_controller&.refresh_annotations
            rescue *BOUNDARY_ERRORS => e
              @logger&.debug("AnnotationOverlayController.refresh_annotations failed: #{e.message}")
            end

            def activate_session
              raise ArgumentError, 'Dependency :input_controller not available' unless @input_controller

              @input_controller.enter_modal_mode(:annotation_editor)
              true
            rescue ArgumentError => e
              log_dependency_error(:activate_annotation_editor_overlay_session, e)
              false
            end

            def deactivate_session
              @input_controller&.exit_modal_mode(:annotation_editor)
            end

            def cleanup_fallback
              @ui_session&.close_editor || @reader_session_mutator.update_reader(annotation_editor_overlay: nil)
              deactivate_session
            end

            def log_dependency_error(context, error)
              @logger&.error('Annotation editor activation failed', context: context, error: error.message)
            end

            def normalize_payload(payload)
              return payload unless payload.is_a?(Hash)

              payload.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }
            end
          end
        end
      end
    end
  end
end
