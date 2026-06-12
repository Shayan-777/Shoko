# frozen_string_literal: true

require_relative '../../requests/cursor_move'
require_relative '../../requests/selection_delta'
require_relative '../../requests/edit_op'
require_relative '../../support/intent_action_group'
require_relative '../../support/menu_session_access'
require_relative '../../../services/annotation_edit/operator'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          # Handles annotations browsing and annotation-editor intents from the menu.
          class Annotations
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess

            SELECTION_MOVE_INTENTS = %i[move_annotation_selection_up move_annotation_selection_down].freeze
            SUPPORTED_INTENTS = %i[
              open_annotations_mode
              move_annotation_selection_up
              move_annotation_selection_down
              activate_annotation_selection
              open_selected_annotation
              edit_selected_annotation
              delete_selected_annotation
              edit_annotation_text
              move_annotation_cursor
              annotation_editor_save
              annotation_editor_cancel
            ].freeze

            def initialize(menu_session_store:, menu_annotation_control:, annotation_workflow:,
                           annotation_service:, menu_transient_store:, logger: nil)
              assign_menu_session_store!(menu_session_store, menu_transient_store: menu_transient_store)
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
                :annotation_editor_save,
                :annotation_editor_cancel
              ).merge(delta_payloads(*SELECTION_MOVE_INTENTS))
                .merge(edit_op_payloads(:edit_annotation_text))
                .merge(direction_payloads(:move_annotation_cursor))
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
                edit_annotation_text: route(payload: :edit_op, result: :handled) do |op|
                  operator.apply(op)
                end,
              }
            end

            def editor_cursor_routes
              {
                move_annotation_cursor: route(payload: :direction, result: :handled) do |direction|
                  @menu_annotation_control.move_annotation_cursor(direction: direction)
                end,
              }
            end

            def operator
              @operator ||= Shoko::Application::Services::AnnotationEdit::Operator.new(
                text_reader: -> { current_menu.annotation_edit_text },
                cursor_reader: -> { current_menu.annotation_edit_cursor },
                writer: lambda do |text:, cursor:|
                  update_menu(annotation_edit_text: text, annotation_edit_cursor: cursor)
                end
              )
            end

            def editor_completion_routes
              {
                annotation_editor_save: route { save_annotation_edit },
                annotation_editor_cancel: route { cancel_annotation_edit },
              }
            end

            def open_annotations_mode
              preload_annotations
              update_menu(mode: :annotations, browse_selected: 0)
              :handled
            end

            def activate_annotation_selection
              context = @menu_annotation_control.selected_annotation_context
              return :pass unless context && context[:annotation] && context[:book_path]

              update_menu(
                selected_annotation: context[:annotation],
                selected_annotation_book: context[:book_path],
                mode: :annotation_detail,
                browse_selected: 0
              )
              :handled
            end

            def save_annotation_edit
              @annotation_workflow.save_current_annotation_edit
              :handled
            end

            def cancel_annotation_edit
              @annotation_workflow.cancel_current_annotation_edit
              :handled
            end

            def preload_annotations
              annotations = @annotation_service ? @annotation_service.list_all : {}
              update_menu(annotations_all: annotations || {})
            rescue Shoko::Error => e
              @logger&.error('menu.preload_annotations.failed', error: e.class.name, message: e.message)
              update_menu(annotations_all: {})
            end
          end
        end
      end
    end
  end
end
