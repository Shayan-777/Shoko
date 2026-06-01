# frozen_string_literal: true

require_relative '../support/message_notifier'
require_relative '../support/session_outcome_helpers'

module Shoko
  module Adapters
    module Input
      module Controllers
        class AnnotationOverlayController
          # Handles the annotations overlay list lifecycle and actions.
          class AnnotationsWorkflow
            include Shoko::Adapters::Input::Controllers::Support::MessageNotifier
            include Shoko::Adapters::Input::Controllers::Support::SessionOutcomeHelpers

            BOUNDARY_ERRORS = [ArgumentError, TypeError, RuntimeError].freeze

            def initialize(reader_state:, reader_session_mutator:, state_controller:, ui_session:,
                           notification_service:, logger:, open_editor:)
              @reader_state = reader_state
              @reader_session_mutator = reader_session_mutator
              @state_controller = state_controller
              @ui_session = ui_session
              @notification_service = notification_service
              @logger = logger
              @open_editor = open_editor
            end

            def open
              raise ArgumentError, 'Dependency :annotation_overlay_ui_session not available' unless @ui_session

              outcome = @ui_session.open_annotations
              return unless session_ok?(outcome)

              set_message('Annotations overlay open (up/down navigate, Enter open, e edit, d delete)', 3)
            rescue *BOUNDARY_ERRORS => e
              @logger&.debug("AnnotationOverlayController.show_annotations_overlay failed: #{e.message}")
              cleanup_fallback
            end

            def close
              @ui_session&.close_annotations
            rescue *BOUNDARY_ERRORS => e
              @logger&.debug("AnnotationOverlayController.close_annotations_overlay failed: #{e.message}")
              cleanup_fallback
            end

            def open_annotation(annotation)
              with_normalized_annotation(annotation) do |normalized|
                @state_controller&.jump_to_annotation(normalized)
                close
              end
            rescue *BOUNDARY_ERRORS => e
              @logger&.debug("AnnotationOverlayController.open_annotation_from_overlay failed: #{e.message}")
              close
            end

            def edit_annotation(annotation)
              with_normalized_annotation(annotation) do |normalized|
                close
                @open_editor.call(
                  text: normalized[:text],
                  range: normalized[:range],
                  chapter_index: normalized[:chapter_index],
                  annotation: normalized
                )
              end
            end

            def delete_annotation(annotation)
              with_normalized_annotation(annotation) do |normalized|
                new_index = @state_controller&.delete_annotation_by_id(normalized)
                @ui_session&.update_annotations_selected_index(new_index) unless new_index.nil?

                close if Array(@reader_state.annotations).empty?
                set_message('Annotation deleted', 2)
              end
            rescue *BOUNDARY_ERRORS => e
              @logger&.debug("AnnotationOverlayController.delete_annotation_from_overlay failed: #{e.message}")
              close
            end

            def process_event(result)
              payload = normalize_payload(session_payload(result))
              return :pass unless payload.is_a?(Hash)

              handle_payload(payload[:type], payload)
            end

            def visible?
              @ui_session&.annotations_visible? == true
            end

            def refresh_annotations
              @state_controller&.refresh_annotations
            rescue *BOUNDARY_ERRORS => e
              @logger&.debug("AnnotationOverlayController.refresh_annotations failed: #{e.message}")
            end

            private

            def normalize_annotation(annotation)
              return nil unless annotation.is_a?(Hash)

              annotation.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }
            end

            def normalize_payload(payload)
              return payload unless payload.is_a?(Hash)

              payload.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }
            end

            def with_normalized_annotation(annotation)
              normalized = normalize_annotation(annotation)
              return unless normalized

              yield normalized
            end

            def handle_payload(type, payload)
              case type
              when :selection_change then update_selection(payload[:index])
              when :open then handle_annotation_action(payload[:annotation], :open)
              when :edit then handle_annotation_action(payload[:annotation], :edit)
              when :delete then handle_annotation_action(payload[:annotation], :delete)
              when :close then close_and_handle
              else :pass
              end
            end

            def update_selection(index)
              @reader_session_mutator&.update_sidebar(
                annotations_selected: index,
                sidebar_annotations_selected: index
              )
              :handled
            end

            def handle_annotation_action(annotation, action)
              case action
              when :open then open_annotation(annotation)
              when :edit then edit_annotation(annotation)
              when :delete then delete_annotation(annotation)
              end
              :handled
            end

            def close_and_handle
              close
              :handled
            end

            def cleanup_fallback
              @ui_session&.close_annotations || @reader_session_mutator.update_reader(annotations_overlay: nil)
            rescue *BOUNDARY_ERRORS => e
              @logger&.debug("AnnotationOverlayController.cleanup_annotations_overlay_fallback failed: #{e.message}")
              nil
            end
          end
        end
      end
    end
  end
end
