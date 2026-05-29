# frozen_string_literal: true

require_relative 'annotation_overlay/annotations_workflow'
require_relative 'annotation_overlay/editor_workflow'
require_relative 'annotation_overlay/spellcheck_coordinator'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Handles annotation overlay functionality through smaller adapter-local workflows.
        class AnnotationOverlayController
          StateDependencies = Data.define(:reader_state, :reader_session_mutator, :state_controller)
          ServiceDependencies = Data.define(:annotation_service, :dictionary_service)
          InputDependencies = Data.define(:input_controller, :annotation_overlay_ui_session)
          NotificationDependencies = Data.define(:notification_service, :logger)
          Dependencies = Data.define(:state, :services, :input, :notifications) do
            def self.build(reader_state:, reader_session_mutator:, notification_service:, state_controller: nil,
                           annotation_service: nil, dictionary_service: nil,
                           input_controller: nil, annotation_overlay_ui_session: nil, logger: nil)
              new(
                state: build_state(reader_state, reader_session_mutator, state_controller),
                services: build_services(annotation_service, dictionary_service),
                input: build_input(input_controller, annotation_overlay_ui_session),
                notifications: build_notifications(notification_service, logger)
              )
            end

            def validate!
              raise ArgumentError, 'notification_service is required' if notifications.notification_service.nil?

              self
            end

            def self.build_state(reader_state, reader_session_mutator, state_controller)
              StateDependencies.new(
                reader_state: reader_state,
                reader_session_mutator: reader_session_mutator,
                state_controller: state_controller
              )
            end

            def self.build_services(annotation_service, dictionary_service)
              ServiceDependencies.new(annotation_service: annotation_service, dictionary_service: dictionary_service)
            end

            def self.build_input(input_controller, annotation_overlay_ui_session)
              InputDependencies.new(
                input_controller: input_controller,
                annotation_overlay_ui_session: annotation_overlay_ui_session
              )
            end

            def self.build_notifications(notification_service, logger)
              NotificationDependencies.new(notification_service: notification_service, logger: logger)
            end
          end

          def initialize(deps:)
            dependencies = deps.validate!
            @reader_state = dependencies.state.reader_state
            @annotation_overlay_ui_session = dependencies.input.annotation_overlay_ui_session
            build_workflows(dependencies)
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
            @annotations_workflow.open
          end

          def close_annotations_overlay
            @annotations_workflow.close
          end

          def show_annotation_editor_overlay(text:, range:, chapter_index:, annotation: nil)
            @editor_workflow.open(text: text, range: range, chapter_index: chapter_index, annotation: annotation)
          end

          def close_annotation_editor_overlay
            @editor_workflow.close
          end

          def open_annotation_from_overlay(annotation)
            @annotations_workflow.open_annotation(annotation)
          end

          def edit_annotation_from_overlay(annotation)
            @annotations_workflow.edit_annotation(annotation)
          end

          def delete_annotation_from_overlay(annotation)
            @annotations_workflow.delete_annotation(annotation)
          end

          def handle_annotation_editor_overlay_event(result)
            @editor_workflow.handle_event(result)
          end

          def annotations_up
            @annotations_workflow.process_event(@annotation_overlay_ui_session&.annotations_up)
          end

          def annotations_down
            @annotations_workflow.process_event(@annotation_overlay_ui_session&.annotations_down)
          end

          def annotations_open
            @annotations_workflow.process_event(@annotation_overlay_ui_session&.annotations_open)
          end

          def annotations_edit
            @annotations_workflow.process_event(@annotation_overlay_ui_session&.annotations_edit)
          end

          def annotations_delete
            @annotations_workflow.process_event(@annotation_overlay_ui_session&.annotations_delete)
          end

          def annotations_cancel
            @annotations_workflow.process_event(@annotation_overlay_ui_session&.annotations_cancel)
          end

          def annotation_editor_move_left
            @editor_workflow.process_event(@annotation_overlay_ui_session&.editor_move_left)
          end

          def annotation_editor_move_right
            @editor_workflow.process_event(@annotation_overlay_ui_session&.editor_move_right)
          end

          def annotation_editor_move_up
            @editor_workflow.process_event(@annotation_overlay_ui_session&.editor_move_up)
          end

          def annotation_editor_move_down
            @editor_workflow.process_event(@annotation_overlay_ui_session&.editor_move_down)
          end

          def annotation_editor_spellcheck
            @editor_workflow.spellcheck
          end

          def handle_annotation_editor_overlay_click(col, row)
            @editor_workflow.handle_click(col, row)
          end

          def annotations_overlay_visible?
            @annotations_workflow.visible?
          end

          def annotation_editor_visible?
            @editor_workflow.visible?
          end

          def refresh_theme(theme_context:)
            @editor_workflow.refresh_theme(theme_context: theme_context)
          end

          def refresh_annotations
            @annotations_workflow.refresh_annotations
          end

          def current_book_path
            @reader_state.book_path
          end

          private

          def build_workflows(dependencies)
            spellcheck = build_spellcheck_coordinator(dependencies)
            @editor_workflow = build_editor_workflow(dependencies, spellcheck)
            @annotations_workflow = build_annotations_workflow(dependencies)
          end

          def build_spellcheck_coordinator(dependencies)
            SpellcheckCoordinator.new(
              dictionary_service: dependencies.services.dictionary_service,
              ui_session: @annotation_overlay_ui_session,
              notification_service: dependencies.notifications.notification_service,
              logger: dependencies.notifications.logger
            )
          end

          def build_editor_workflow(dependencies, spellcheck)
            EditorWorkflow.new(
              reader_state: dependencies.state.reader_state,
              reader_session_mutator: dependencies.state.reader_session_mutator,
              state_controller: dependencies.state.state_controller,
              annotation_service: dependencies.services.annotation_service,
              input_controller: dependencies.input.input_controller,
              ui_session: @annotation_overlay_ui_session,
              notification_service: dependencies.notifications.notification_service,
              logger: dependencies.notifications.logger,
              spellcheck_coordinator: spellcheck
            )
          end

          def build_annotations_workflow(dependencies)
            AnnotationsWorkflow.new(
              reader_state: dependencies.state.reader_state,
              reader_session_mutator: dependencies.state.reader_session_mutator,
              state_controller: dependencies.state.state_controller,
              ui_session: @annotation_overlay_ui_session,
              notification_service: dependencies.notifications.notification_service,
              logger: dependencies.notifications.logger,
              open_editor: ->(**kwargs) { @editor_workflow.open(**kwargs) }
            )
          end
        end
      end
    end
  end
end
