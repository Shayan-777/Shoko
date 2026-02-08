# frozen_string_literal: true

require_relative '../../annotation_editor_overlay_session'

module Shoko
  module Application
    module Controllers
      module Reader
        # Owns lifecycle of the annotation editor overlay session.
        class OverlaySessionCoordinator
          def initialize(ui_controller:, reader_state:, state_writer:, annotation_service:)
            @ui_controller = ui_controller
            @reader_state = reader_state
            @state_writer = state_writer
            @annotation_service = annotation_service
            @overlay_session = nil
          end

          def activate
            return @overlay_session if @overlay_session

            @overlay_session = Shoko::Application::AnnotationEditorOverlaySession.new(
              nil,
              @ui_controller,
              reader_state: @reader_state,
              state_writer: @state_writer,
              annotation_service: @annotation_service
            )
          end

          def deactivate
            @overlay_session = nil
          end

          def current_component
            return @overlay_session if @overlay_session&.active?

            deactivate
            @ui_controller.current_mode
          end
        end
      end
    end
  end
end
