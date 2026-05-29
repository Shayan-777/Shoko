# frozen_string_literal: true

require_relative '../../requests/edit_op'
require_relative '../../support/intent_action_group'
require_relative '../../support/text_editing'
require_relative '../../support/menu_session_access'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          # Handles inline browse-search editing intents.
          class Search
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess

            SUPPORTED_INTENTS = %i[edit_browse_search].freeze

            def initialize(menu_session_store:, menu_transient_store:)
              assign_menu_session_store!(menu_session_store, menu_transient_store: menu_transient_store)
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported menu search intent')
            end

            private

            def routes
              @routes ||= {
                edit_browse_search: route(payload: :edit_op, result: :handled) do |op|
                  update_query(op.operation, op.text)
                end,
              }.freeze
            end

            def supported_payloads
              edit_op_payloads(:edit_browse_search)
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
