# frozen_string_literal: true

require_relative '../../requests/text_input'
require_relative '../../support/intent_action_group'
require_relative '../../support/text_editing'
require_relative '../../support/menu_session_access'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Search
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess

            SUPPORTED_INTENTS = %i[
              browse_insert_text
              browse_backspace
              browse_delete
            ].freeze

            def initialize(menu_session_store:)
              assign_menu_session_store!(menu_session_store)
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported menu search intent')
            end

            private

            def routes
              @routes ||= {
                browse_insert_text: route(payload: :text) { |text| update_query(:insert, text) },
                browse_backspace: route(result: :handled) { update_query(:backspace) },
                browse_delete: route(result: :handled) { update_query(:delete) },
              }.freeze
            end

            def supported_payloads
              {
                browse_insert_text: [Shoko::Application::UseCases::Requests::TextInput],
                browse_backspace: [NilClass],
                browse_delete: [NilClass],
              }
            end

            def update_query(operation, text = nil)
              menu = current_menu
              current = menu.search_query.to_s
              cursor = (menu.search_cursor || current.length).to_i
              next_text, next_cursor = Shoko::Application::UseCases::Support::TextEditing.apply_edit(
                current,
                cursor,
                operation,
                text: text
              )
              update_menu(search_query: next_text, search_cursor: next_cursor)
              :handled
            end
          end
        end
      end
    end
  end
end
