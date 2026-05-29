# frozen_string_literal: true

require_relative '../../requests/selection_delta'
require_relative '../../requests/edit_op'
require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Reader
        module Actions
          # Routes in-book search intents to the reader search control surface.
          class Search
            include Shoko::Application::UseCases::Support::IntentActionGroup

            SUPPORTED_INTENTS = %i[
              open_in_book_search
              close_in_book_search
              edit_in_book_search
              search_confirm
              search_move_up
              search_move_down
            ].freeze

            def initialize(reader_search_control:)
              @reader_search_control = reader_search_control
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported reader search intent')
            end

            private

            def routes
              @routes ||= {
                open_in_book_search: route(result: :handled) { @reader_search_control.open_search_session },
                close_in_book_search: route(result: :handled) { @reader_search_control.close_search_session },
                edit_in_book_search: route(payload: :edit_op, result: :handled) do |op|
                  apply_search_edit(op)
                end,
                search_confirm: route(result: :handled) { @reader_search_control.submit_search_session },
                search_move_up: route(payload: :delta, result: :handled) do |delta|
                  @reader_search_control.move_search_selection(delta: delta)
                end,
                search_move_down: route(payload: :delta, result: :handled) do |delta|
                  @reader_search_control.move_search_selection(delta: delta)
                end,
              }.freeze
            end

            def supported_payloads
              {
                open_in_book_search: [NilClass],
                close_in_book_search: [NilClass],
                edit_in_book_search: [Shoko::Application::UseCases::Requests::EditOp],
                search_confirm: [NilClass],
                search_move_up: [Shoko::Application::UseCases::Requests::SelectionDelta],
                search_move_down: [Shoko::Application::UseCases::Requests::SelectionDelta],
              }
            end

            def apply_search_edit(op)
              case op.operation
              when :insert    then @reader_search_control.append_search_text(op.text)
              when :backspace then @reader_search_control.delete_search_character
              end
            end
          end
        end
      end
    end
  end
end
