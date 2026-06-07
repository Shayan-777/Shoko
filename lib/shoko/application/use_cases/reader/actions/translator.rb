# frozen_string_literal: true

require_relative '../../requests/cursor_move'
require_relative '../../requests/edit_op'
require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Reader
        module Actions
          # Routes in-book translator intents. The translator card is an overlay
          # reader mode (a sibling of in-book search, the dictionary card, and the
          # TOC panel), so the bottom bar becomes a "Translate" source-text input
          # while the card shows the translation — or, with the picker open, a
          # filterable language list — above it.
          #
          # The text field, the language pair, the result, and the picker selection
          # all need adapter coordination (the translation service, the language
          # list, and the contextual text-vs-picker routing), so — unlike search,
          # which edits its query in the use case — these delegate to the control
          # port (adapter/document-bound).
          class Translator
            include Shoko::Application::UseCases::Support::IntentActionGroup

            SUPPORTED_INTENTS = %i[
              open_translator
              close_translator
              edit_translator
              translator_confirm
              translator_cursor_move
              translator_cycle_picker
              translator_swap_languages
            ].freeze

            def initialize(reader_translator_control:)
              @reader_translator_control = reader_translator_control
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported reader translator intent')
            end

            private

            def routes
              @routes ||= {
                open_translator: route(payload: :raw, result: :handled) do |payload|
                  @reader_translator_control.open_translator_session(payload)
                end,
                close_translator: route(result: :handled) { @reader_translator_control.close_translator_session },
                edit_translator: route(payload: :edit_op, result: :handled) do |op|
                  @reader_translator_control.edit_translator_input(op)
                end,
                translator_confirm: route(result: :handled) { @reader_translator_control.confirm_translator },
                translator_cursor_move: route(payload: :direction, result: :handled) do |direction|
                  @reader_translator_control.move_translator_cursor(direction)
                end,
                translator_cycle_picker: route(result: :handled) do
                  @reader_translator_control.cycle_translator_picker
                end,
                translator_swap_languages: route(result: :handled) do
                  @reader_translator_control.swap_translator_languages
                end,
              }.freeze
            end

            def supported_payloads
              {
                open_translator: [NilClass, Hash],
                close_translator: [NilClass],
                edit_translator: [Shoko::Application::UseCases::Requests::EditOp],
                translator_confirm: [NilClass],
                translator_cursor_move: [Shoko::Application::UseCases::Requests::CursorMove],
                translator_cycle_picker: [NilClass],
                translator_swap_languages: [NilClass],
              }
            end
          end
        end
      end
    end
  end
end
