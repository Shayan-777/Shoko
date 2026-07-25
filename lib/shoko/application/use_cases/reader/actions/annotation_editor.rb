# frozen_string_literal: true

require 'shoko/application/use_cases/support/editor_text_routes'
require_relative '../../requests/cursor_move'
require_relative '../../requests/edit_op'
require_relative '../../support/intent_action_group'
require 'shoko/application/services/annotation_edit/operator'

module Shoko
  module Application
    module UseCases
      module Reader
        module Actions
          # Routes annotation editor intents. Text mutations write directly
          # through the operator + reader_session_mutator; save/cancel run
          # application-side against the annotation_service and clear state
          # through the editor control port's close hook.
          class AnnotationEditor
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::EditorTextRoutes

            SUPPORTED_INTENTS = %i[
              edit_annotation_text
              move_annotation_cursor
              annotation_editor_save
              annotation_editor_cancel
              annotation_editor_spellcheck
              annotation_editor_confirm
            ].freeze

            def initialize(reader_session_store:, reader_view_state_store:, reader_view_mutator:,
                           reader_annotation_editor_control:, annotation_service:,
                           notification_writer:)
              @reader_session_store = reader_session_store
              @reader_view_state_store = reader_view_state_store
              @reader_view_mutator = reader_view_mutator
              @reader_annotation_editor_control = reader_annotation_editor_control
              @annotation_service = annotation_service
              @notification_writer = notification_writer
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported reader annotation editor intent')
            end

            private

            def routes
              @routes ||= editor_text_routes.merge(editor_movement_routes).merge(editor_command_routes).freeze
            end

            def supported_payloads
              edit_op_payloads(:edit_annotation_text)
                .merge(direction_payloads(:move_annotation_cursor))
                .merge(nil_payloads(:annotation_editor_save,
                                    :annotation_editor_cancel,
                                    :annotation_editor_spellcheck,
                                    :annotation_editor_confirm))
                .freeze
            end

            def editor_movement_routes
              {
                move_annotation_cursor: route(payload: :direction, result: :handled) do |direction|
                  @reader_annotation_editor_control.move_annotation_cursor(direction: direction)
                end,
              }
            end

            def editor_command_routes
              handled_routes(:annotation_editor_save) { save_annotation }
                .merge(handled_routes(:annotation_editor_cancel) { cancel_annotation })
                .merge(handled_routes(:annotation_editor_spellcheck) do
                  @reader_annotation_editor_control.spellcheck_annotation
                end)
                .merge(handled_routes(:annotation_editor_confirm) do
                  @reader_annotation_editor_control.confirm_annotation_editor
                end)
            end

            def operator
              @operator ||= Shoko::Application::Services::AnnotationEdit::Operator.new(
                text_reader: -> { view_snapshot.annotation_editor_note },
                cursor_reader: -> { view_snapshot.annotation_editor_cursor },
                writer: lambda do |text:, cursor:|
                  @reader_view_mutator.update_reader(
                    annotation_editor_note: text,
                    annotation_editor_cursor: cursor
                  )
                end
              )
            end

            def view_snapshot
              @reader_view_state_store.load
            end

            def save_annotation
              path = @reader_session_store.load.book_path
              return cancel_annotation unless path && @annotation_service

              persist_annotation(path, view_snapshot)
              refresh_annotations(path)
            rescue Shoko::Error => e
              @notification_writer&.show_message("Save failed: #{e.message}")
            ensure
              @reader_view_mutator.update_reader(selection: nil)
              @reader_annotation_editor_control.close_annotation_editor
            end

            def cancel_annotation
              @notification_writer&.show_message('Annotation cancelled')
              @reader_view_mutator.update_reader(selection: nil)
              @reader_annotation_editor_control.close_annotation_editor
            end

            # The editor is only ever opened on an existing annotation (the
            # annotations overlay's edit action), so saving updates the note in
            # place. New annotations are created from a live selection through
            # the notes flow, which captures a document anchor.
            def persist_annotation(path, current)
              annotation_id = current.annotation_editor_annotation_id
              return unless annotation_id

              note = (current.annotation_editor_note || '').to_s
              @annotation_service.update(path, annotation_id, note)
              @notification_writer&.show_message('Annotation updated')
            end

            def refresh_annotations(path)
              @reader_view_mutator.update_reader(annotations: @annotation_service.list_for_book(path))
            end
          end
        end
      end
    end
  end
end
