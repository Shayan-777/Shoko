# frozen_string_literal: true

require_relative '../../requests/text_input'
require_relative '../../support/intent_action_group'
require_relative '../../support/text_editing'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Search
            include Shoko::Application::UseCases::Support::IntentActionGroup

            SUPPORTED_INTENTS = %i[
              browse_insert_text
              browse_backspace
              browse_delete
            ].freeze

            def initialize(menu_state_reader:, menu_session_mutator:)
              @menu_state_reader = menu_state_reader
              @menu_session_mutator = menu_session_mutator
            end

            def call(intent, payload = nil)
              case intent
              when :browse_insert_text
                update_query(:insert, text_from(payload, intent))
              when :browse_backspace
                validate_payload!(intent, payload)
                update_query(:backspace)
              when :browse_delete
                validate_payload!(intent, payload)
                update_query(:delete)
              else
                raise ArgumentError, "unsupported menu search intent: #{intent}"
              end
            end

            private

            def supported_payloads
              {
                browse_insert_text: [Shoko::Application::UseCases::Requests::TextInput],
                browse_backspace: [NilClass],
                browse_delete: [NilClass],
              }
            end

            def update_query(operation, text = nil)
              current = @menu_state_reader.search_query.to_s
              cursor = (@menu_state_reader.search_cursor || current.length).to_i
              next_text, next_cursor = Shoko::Application::UseCases::Support::TextEditing.apply_edit(
                current,
                cursor,
                operation,
                text: text
              )
              @menu_session_mutator.update_menu(search_query: next_text, search_cursor: next_cursor)
              :handled
            end
          end
        end
      end
    end
  end
end
