# frozen_string_literal: true

require_relative '../support/session_outcome_support'

module Shoko
  module Adapters
    module Ui
      module Sessions
        module AnnotationOverlayUiSession
          # Reads overlay/editor components and related rendered content state.
          module OverlayAccess
            def annotations_visible?
              overlay = annotations_overlay
              overlay&.visible?
            rescue *Support::SessionOutcomeSupport::RESCUABLE_ERRORS => e
              log_error('annotation.session.annotations_visible?', e)
              false
            end

            def annotation_editor_visible?
              overlay = annotation_editor_overlay
              overlay&.visible?
            rescue *Support::SessionOutcomeSupport::RESCUABLE_ERRORS => e
              log_error('annotation.session.annotation_editor_visible?', e)
              false
            end

            private

            def annotations_overlay
              @reader_state_reader.annotations_overlay
            rescue *Support::SessionOutcomeSupport::RESCUABLE_ERRORS => e
              log_error('annotation.session.annotations_overlay', e)
              nil
            end

            def annotation_editor_overlay
              @reader_state_reader.annotation_editor_overlay
            rescue *Support::SessionOutcomeSupport::RESCUABLE_ERRORS => e
              log_error('annotation.session.annotation_editor_overlay', e)
              nil
            end

            def current_rendered_lines
              lines = @rendered_content_reader&.rendered_lines
              lines.is_a?(Hash) ? lines : {}
            rescue *Support::SessionOutcomeSupport::RESCUABLE_ERRORS => e
              log_error('annotation.session.current_rendered_lines', e)
              {}
            end

            def current_annotation
              overlay = annotations_overlay
              return nil unless overlay

              overlay.current_annotation
            rescue *Support::SessionOutcomeSupport::RESCUABLE_ERRORS => e
              log_error('annotation.session.current_annotation', e)
              nil
            end
          end
        end
      end
    end
  end
end
