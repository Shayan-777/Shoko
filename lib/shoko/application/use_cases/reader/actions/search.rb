# frozen_string_literal: true

require_relative '../../requests/selection_delta'
require_relative '../../requests/text_input'
require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Reader
        module Actions
          class Search
            include Shoko::Application::UseCases::Support::IntentActionGroup

            SUPPORTED_INTENTS = %i[
              open_in_book_search
              close_in_book_search
              search_insert_text
              search_backspace
              search_confirm
              search_move_up
              search_move_down
            ].freeze

            def initialize(reader_search_control:)
              @reader_search_control = reader_search_control
            end

            def call(intent, payload = nil)
              case intent
              when :open_in_book_search
                validate_payload!(intent, payload)
                @reader_search_control.open_search_session
              when :close_in_book_search
                validate_payload!(intent, payload)
                @reader_search_control.close_search_session
              when :search_insert_text
                @reader_search_control.append_search_text(text_from(payload, intent))
              when :search_backspace
                validate_payload!(intent, payload)
                @reader_search_control.delete_search_character
              when :search_confirm
                validate_payload!(intent, payload)
                @reader_search_control.submit_search_session
              when :search_move_up
                @reader_search_control.move_search_selection(delta: positive_delta(payload, intent))
              when :search_move_down
                @reader_search_control.move_search_selection(delta: positive_delta(payload, intent))
              else
                raise ArgumentError, "unsupported reader search intent: #{intent}"
              end

              :handled
            end

            private

            def supported_payloads
              {
                open_in_book_search: [NilClass],
                close_in_book_search: [NilClass],
                search_insert_text: [Shoko::Application::UseCases::Requests::TextInput],
                search_backspace: [NilClass],
                search_confirm: [NilClass],
                search_move_up: [Shoko::Application::UseCases::Requests::SelectionDelta],
                search_move_down: [Shoko::Application::UseCases::Requests::SelectionDelta],
              }
            end
          end
        end
      end
    end
  end
end
