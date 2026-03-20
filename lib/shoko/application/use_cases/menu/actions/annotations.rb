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
          # Handles annotations browsing and annotation-editor intents from the menu.
          class Annotations
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess
            include SessionFlow

            SELECTION_MOVE_INTENTS = %i[move_annotation_selection_up move_annotation_selection_down].freeze
            CURSOR_MOVE_INTENTS = %i[
              annotation_editor_move_left
              annotation_editor_move_right
              annotation_editor_move_up
              annotation_editor_move_down
            ].freeze
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
                           annotation_service:, menu_transient_store: nil, logger: nil)
              assign_menu_session_store!(menu_session_store, menu_transient_store: menu_transient_store)
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
              @routes ||= annotation_routes.merge(editor_routes).freeze
            end

            def supported_payloads
              nil_payloads(
                :open_annotations_mode,
                :activate_annotation_selection,
                :open_selected_annotation,
                :edit_selected_annotation,
                :delete_selected_annotation,
                :annotation_editor_backspace,
                :annotation_editor_newline,
                :annotation_editor_save,
                :annotation_editor_cancel
              ).merge(delta_payloads(*SELECTION_MOVE_INTENTS))
                .merge(text_payloads(:annotation_editor_insert_text))
                .merge(direction_payloads(*CURSOR_MOVE_INTENTS))
            end

            def annotation_routes
              {
                open_annotations_mode: route(result: :handled) { open_annotations_mode },
                activate_annotation_selection: route { activate_annotation_selection },
                open_selected_annotation: route(result: :handled) { @annotation_workflow.open_selected_annotation },
                edit_selected_annotation: route(result: :handled) do
                  @annotation_workflow.open_selected_annotation_for_edit
                end,
                delete_selected_annotation: route(result: :handled) do
                  @annotation_workflow.delete_selected_annotation
                end,
              }.merge(
                handled_routes(*SELECTION_MOVE_INTENTS, payload: :delta) do |delta|
                  @menu_annotation_control.move_annotation_selection(delta: delta)
                end
              )
            end

            def editor_routes
              editor_text_routes.merge(editor_cursor_routes).merge(editor_completion_routes)
            end

            def editor_text_routes
              {
                annotation_editor_insert_text: route(payload: :text) do |text|
                  @menu_annotation_control.append_annotation_text(text)
                end,
                annotation_editor_backspace: route(result: :handled) do
                  @menu_annotation_control.delete_annotation_character
                end,
                annotation_editor_newline: route(result: :handled) do
                  @menu_annotation_control.insert_annotation_newline
                end,
              }
            end

            def editor_cursor_routes
              handled_routes(*CURSOR_MOVE_INTENTS, payload: :direction) do |direction|
                @menu_annotation_control.move_annotation_cursor(direction: direction)
              end
            end

            def editor_completion_routes
              {
                annotation_editor_save: route { save_annotation_edit },
                annotation_editor_cancel: route { cancel_annotation_edit },
              }
            end
          end
        end
      end
    end
  end
end
