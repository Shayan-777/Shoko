# frozen_string_literal: true

require_relative '../support/session_outcome_helpers'

module Shoko
  module Adapters
    module Ui
      module Sessions
        module AnnotationOverlayUiSession
          # Dispatches annotation list overlay commands and selection events.
          module AnnotationDispatch
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

            private

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
          end
        end
      end
    end
  end
end
