# frozen_string_literal: true

require_relative '../../../../shared/menu_definitions'
require_relative '../../requests/mode_change'
require_relative '../../requests/selection_delta'
require_relative '../../requests/text_input'
require_relative 'dictionary/mode_flow'
require_relative 'dictionary/query_support'
require_relative 'dictionary/selection_flow'
require_relative '../../support/intent_action_group'
require_relative '../../support/menu_session_access'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          # Handles dictionary mode, query, and selection intents from the menu.
          class Dictionary
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess
            include ModeFlow
            include QuerySupport
            include SelectionFlow

            MODE_INTENTS = %i[open_dictionary_mode close_dictionary_mode].freeze
            MOVE_INTENTS = %i[move_dictionary_selection_up move_dictionary_selection_down].freeze
            SUPPORTED_INTENTS = %i[
              open_dictionary_mode
              close_dictionary_mode
              refresh_dictionary_results
              move_dictionary_selection_up
              move_dictionary_selection_down
              activate_dictionary_selection
              dictionary_query_insert_text
              dictionary_query_backspace
              dictionary_query_delete
              submit_dictionary_query
            ].freeze

            def initialize(menu_session_store:, menu_mode_control:, dictionary_workflow:, settings_service:,
                           menu_transient_store: nil)
              assign_menu_session_store!(menu_session_store, menu_transient_store: menu_transient_store)
              @menu_mode_control = menu_mode_control
              @dictionary_workflow = dictionary_workflow
              @settings_service = settings_service
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported menu dictionary intent')
            end

            private

            def routes
              @routes ||= mode_routes.merge(selection_routes).merge(query_routes).freeze
            end

            def supported_payloads
              mode_payloads(*MODE_INTENTS, allow_nil: true)
                .merge(delta_payloads(*MOVE_INTENTS))
                .merge(text_payloads(:dictionary_query_insert_text))
                .merge(
                  nil_payloads(
                    :refresh_dictionary_results,
                    :activate_dictionary_selection,
                    :dictionary_query_backspace,
                    :dictionary_query_delete,
                    :submit_dictionary_query
                  )
                )
            end

            def mode_routes
              {
                open_dictionary_mode: route(payload: :mode) { |mode| open_dictionary_mode(mode) },
                close_dictionary_mode: route(payload: :mode) { |mode| close_dictionary_mode(mode) },
                refresh_dictionary_results: route(result: :handled) do
                  @dictionary_workflow.fetch_dictionary_catalog
                end,
              }
            end

            def selection_routes
              handled_routes(*MOVE_INTENTS, payload: :delta) { |delta| move_dictionary_selection(delta) }
                .merge(activate_dictionary_selection: route(result: :handled) { activate_dictionary_selection })
            end

            def query_routes
              {
                dictionary_query_insert_text: route(payload: :text) { |text| update_query(:insert, text) },
                dictionary_query_backspace: route(result: :handled) { update_query(:backspace) },
                dictionary_query_delete: route(result: :handled) { update_query(:delete) },
                submit_dictionary_query: route(result: :handled) { submit_dictionary_query },
              }
            end
          end
        end
      end
    end
  end
end
