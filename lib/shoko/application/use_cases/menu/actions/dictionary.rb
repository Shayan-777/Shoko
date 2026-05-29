# frozen_string_literal: true

require_relative '../../../ports/inbound/menu_catalog'
require_relative '../../requests/mode_change'
require_relative '../../requests/selection_delta'
require_relative '../../requests/edit_op'
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
              edit_menu_dictionary_query
              submit_dictionary_query
            ].freeze

            def initialize(menu_session_store:, dictionary_workflow:, settings_service:,
                           menu_transient_store:)
              assign_menu_session_store!(menu_session_store, menu_transient_store: menu_transient_store)
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
                .merge(edit_op_payloads(:edit_menu_dictionary_query))
                .merge(
                  nil_payloads(
                    :refresh_dictionary_results,
                    :activate_dictionary_selection,
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
                edit_menu_dictionary_query: route(payload: :edit_op, result: :handled) do |op|
                  update_query(op.operation, op.text)
                end,
                submit_dictionary_query: route(result: :handled) { submit_dictionary_query },
              }
            end
          end
        end
      end
    end
  end
end
