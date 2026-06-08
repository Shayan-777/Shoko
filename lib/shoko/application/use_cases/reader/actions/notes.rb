# frozen_string_literal: true

require_relative '../../requests/selection_delta'
require_relative '../../requests/cursor_move'
require_relative '../../requests/edit_op'
require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Reader
        module Actions
          # Routes annotation-notes mode intents. The notes panel is an overlay
          # reader mode (a sibling of in-book search, the dictionary card, the TOC
          # panel, and the translator), so the bottom bar's badge flips to
          # "Annotation Notes" while the panel lists the book's notes above it — or,
          # with the compose editor open, becomes a quiet toolbar over the in-card
          # note editor.
          #
          # Selection movement, jumping, persistence, and the contextual
          # list-vs-editor key routing all need adapter coordination, so — like the
          # TOC and translator action groups — these delegate to the control port.
          class Notes
            include Shoko::Application::UseCases::Support::IntentActionGroup

            SUPPORTED_INTENTS = %i[
              open_notes
              close_notes
              notes_move_up
              notes_move_down
              notes_confirm
              notes_edit
              notes_new
              notes_delete
              edit_note
              note_cursor_move
            ].freeze

            def initialize(reader_notes_control:)
              @reader_notes_control = reader_notes_control
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported reader notes intent')
            end

            private

            def routes
              @routes ||= {
                open_notes: route(payload: :raw, result: :handled) do |payload|
                  @reader_notes_control.open_notes_lookup(payload)
                end,
                close_notes: route(result: :handled) { @reader_notes_control.close_notes_lookup },
                notes_move_up: route(payload: :delta, result: :handled) do |delta|
                  @reader_notes_control.move_notes_selection(delta)
                end,
                notes_move_down: route(payload: :delta, result: :handled) do |delta|
                  @reader_notes_control.move_notes_selection(delta)
                end,
                notes_confirm: route(result: :handled) { @reader_notes_control.confirm_notes_selection },
                notes_edit: route(result: :handled) { @reader_notes_control.edit_selected_note },
                notes_new: route(result: :handled) { @reader_notes_control.new_note },
                notes_delete: route(result: :handled) { @reader_notes_control.delete_selected_note },
                edit_note: route(payload: :edit_op, result: :handled) do |op|
                  @reader_notes_control.edit_note_input(op)
                end,
                note_cursor_move: route(payload: :direction, result: :handled) do |direction|
                  @reader_notes_control.move_note_cursor(direction)
                end,
              }.freeze
            end

            def supported_payloads
              {
                open_notes: [NilClass, Hash],
                close_notes: [NilClass],
                notes_move_up: [Shoko::Application::UseCases::Requests::SelectionDelta],
                notes_move_down: [Shoko::Application::UseCases::Requests::SelectionDelta],
                notes_confirm: [NilClass],
                notes_edit: [NilClass],
                notes_new: [NilClass],
                notes_delete: [NilClass],
                edit_note: [Shoko::Application::UseCases::Requests::EditOp],
                note_cursor_move: [Shoko::Application::UseCases::Requests::CursorMove],
              }
            end
          end
        end
      end
    end
  end
end
