# frozen_string_literal: true

require_relative '../../requests/cursor_move'
require_relative '../../requests/selection_delta'
require_relative '../../requests/text_input'
require_relative 'annotations/session_flow'
require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Annotations
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include SessionFlow

            SUPPORTED_INTENTS = %i[
              open_annotations_mode
              move_annotation_selection_up
              move_annotation_selection_down
              activate_annotation_selection
              open_selected_annotation
              edit_selected_annotation
              delete_selected_annotation
              annotation_editor_insert_text
              annotation_editor_backspace
              annotation_editor_newline
              annotation_editor_move_left
              annotation_editor_move_right
              annotation_editor_move_up
              annotation_editor_move_down
              annotation_editor_save
              annotation_editor_cancel
            ].freeze

            def initialize(menu_session_mutator:, menu_runtime:, annotation_workflow:, annotation_service:, logger: nil)
              @menu_session_mutator = menu_session_mutator
              @menu_runtime = menu_runtime
              @annotation_workflow = annotation_workflow
              @annotation_service = annotation_service
              @logger = logger
            end

            def call(intent, payload = nil)
              case intent
              when :open_annotations_mode
                validate_payload!(intent, payload)
                open_annotations_mode
              when :move_annotation_selection_up
                @menu_runtime.move_annotation_selection(positive_delta(payload, intent))
                :handled
              when :move_annotation_selection_down
                @menu_runtime.move_annotation_selection(positive_delta(payload, intent))
                :handled
              when :activate_annotation_selection
                validate_payload!(intent, payload)
                activate_annotation_selection
              when :open_selected_annotation
                validate_payload!(intent, payload)
                @annotation_workflow.open_selected_annotation
                :handled
              when :edit_selected_annotation
                validate_payload!(intent, payload)
                @annotation_workflow.open_selected_annotation_for_edit
                :handled
              when :delete_selected_annotation
                validate_payload!(intent, payload)
                @annotation_workflow.delete_selected_annotation
                :handled
              when :annotation_editor_insert_text
                @menu_runtime.annotation_editor_insert_text(text_from(payload, intent))
              when :annotation_editor_backspace
                validate_payload!(intent, payload)
                @menu_runtime.annotation_editor_backspace
              when :annotation_editor_newline
                validate_payload!(intent, payload)
                @menu_runtime.annotation_editor_newline
              when :annotation_editor_move_left
                @menu_runtime.annotation_editor_move(direction_from(payload, intent))
              when :annotation_editor_move_right
                @menu_runtime.annotation_editor_move(direction_from(payload, intent))
              when :annotation_editor_move_up
                @menu_runtime.annotation_editor_move(direction_from(payload, intent))
              when :annotation_editor_move_down
                @menu_runtime.annotation_editor_move(direction_from(payload, intent))
              when :annotation_editor_save
                validate_payload!(intent, payload)
                save_annotation_edit
              when :annotation_editor_cancel
                validate_payload!(intent, payload)
                cancel_annotation_edit
              else
                raise ArgumentError, "unsupported menu annotation intent: #{intent}"
              end
            end

            private

            def supported_payloads
              {
                open_annotations_mode: [NilClass],
                move_annotation_selection_up: [Shoko::Application::UseCases::Requests::SelectionDelta],
                move_annotation_selection_down: [Shoko::Application::UseCases::Requests::SelectionDelta],
                activate_annotation_selection: [NilClass],
                open_selected_annotation: [NilClass],
                edit_selected_annotation: [NilClass],
                delete_selected_annotation: [NilClass],
                annotation_editor_insert_text: [Shoko::Application::UseCases::Requests::TextInput],
                annotation_editor_backspace: [NilClass],
                annotation_editor_newline: [NilClass],
                annotation_editor_move_left: [Shoko::Application::UseCases::Requests::CursorMove],
                annotation_editor_move_right: [Shoko::Application::UseCases::Requests::CursorMove],
                annotation_editor_move_up: [Shoko::Application::UseCases::Requests::CursorMove],
                annotation_editor_move_down: [Shoko::Application::UseCases::Requests::CursorMove],
                annotation_editor_save: [NilClass],
                annotation_editor_cancel: [NilClass],
              }
            end
          end
        end
      end
    end
  end
end
