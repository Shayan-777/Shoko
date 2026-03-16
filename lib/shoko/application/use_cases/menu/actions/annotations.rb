# frozen_string_literal: true

require_relative '../../requests/cursor_move'
require_relative '../../requests/selection_delta'
require_relative '../../requests/text_input'
require_relative 'annotations/session_flow'
require_relative '../../support/intent_action_group'
require_relative '../../support/menu_session_access'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Annotations
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess
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

            def initialize(menu_session_store:, menu_mode_control:, menu_annotation_control:, annotation_workflow:,
                           annotation_service:, logger: nil)
              assign_menu_session_store!(menu_session_store)
              @menu_mode_control = menu_mode_control
              @menu_annotation_control = menu_annotation_control
              @annotation_workflow = annotation_workflow
              @annotation_service = annotation_service
              @logger = logger
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported menu annotation intent')
            end

            private

            def routes
              @routes ||= {
                open_annotations_mode: route(result: :handled) { open_annotations_mode },
                move_annotation_selection_up: route(payload: :delta, result: :handled) do |delta|
                  @menu_annotation_control.move_annotation_selection(delta: delta)
                end,
                move_annotation_selection_down: route(payload: :delta, result: :handled) do |delta|
                  @menu_annotation_control.move_annotation_selection(delta: delta)
                end,
                activate_annotation_selection: route { activate_annotation_selection },
                open_selected_annotation: route(result: :handled) { @annotation_workflow.open_selected_annotation },
                edit_selected_annotation: route(result: :handled) do
                  @annotation_workflow.open_selected_annotation_for_edit
                end,
                delete_selected_annotation: route(result: :handled) do
                  @annotation_workflow.delete_selected_annotation
                end,
                annotation_editor_insert_text: route(payload: :text) do |text|
                  @menu_annotation_control.append_annotation_text(text)
                end,
                annotation_editor_backspace: route do
                  @menu_annotation_control.delete_annotation_character
                end,
                annotation_editor_newline: route do
                  @menu_annotation_control.insert_annotation_newline
                end,
                annotation_editor_move_left: route(payload: :direction) do |direction|
                  @menu_annotation_control.move_annotation_cursor(direction: direction)
                end,
                annotation_editor_move_right: route(payload: :direction) do |direction|
                  @menu_annotation_control.move_annotation_cursor(direction: direction)
                end,
                annotation_editor_move_up: route(payload: :direction) do |direction|
                  @menu_annotation_control.move_annotation_cursor(direction: direction)
                end,
                annotation_editor_move_down: route(payload: :direction) do |direction|
                  @menu_annotation_control.move_annotation_cursor(direction: direction)
                end,
                annotation_editor_save: route { save_annotation_edit },
                annotation_editor_cancel: route { cancel_annotation_edit },
              }.freeze
            end

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
