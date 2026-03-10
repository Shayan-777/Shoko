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
          class Dictionary
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess
            include ModeFlow
            include QuerySupport
            include SelectionFlow

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

            def initialize(menu_session_store:, menu_mode_control:, dictionary_workflow:, settings_service:)
              assign_menu_session_store!(menu_session_store)
              @menu_mode_control = menu_mode_control
              @dictionary_workflow = dictionary_workflow
              @settings_service = settings_service
            end

            def call(intent, payload = nil)
              case intent
              when :open_dictionary_mode
                open_dictionary_mode(mode_from(payload, intent))
              when :close_dictionary_mode
                close_dictionary_mode(mode_from(payload, intent))
              when :refresh_dictionary_results
                validate_payload!(intent, payload)
                @dictionary_workflow.fetch_dictionary_catalog
                :handled
              when :move_dictionary_selection_up
                move_dictionary_selection(positive_delta(payload, intent))
              when :move_dictionary_selection_down
                move_dictionary_selection(positive_delta(payload, intent))
              when :activate_dictionary_selection
                validate_payload!(intent, payload)
                activate_dictionary_selection
              when :dictionary_query_insert_text
                update_query(:insert, text_from(payload, intent))
              when :dictionary_query_backspace
                validate_payload!(intent, payload)
                update_query(:backspace)
              when :dictionary_query_delete
                validate_payload!(intent, payload)
                update_query(:delete)
              when :submit_dictionary_query
                validate_payload!(intent, payload)
                submit_dictionary_query
              else
                raise ArgumentError, "unsupported menu dictionary intent: #{intent}"
              end
            end

            private

            def supported_payloads
              {
                open_dictionary_mode: [Shoko::Application::UseCases::Requests::ModeChange, NilClass],
                close_dictionary_mode: [Shoko::Application::UseCases::Requests::ModeChange, NilClass],
                refresh_dictionary_results: [NilClass],
                move_dictionary_selection_up: [Shoko::Application::UseCases::Requests::SelectionDelta],
                move_dictionary_selection_down: [Shoko::Application::UseCases::Requests::SelectionDelta],
                activate_dictionary_selection: [NilClass],
                dictionary_query_insert_text: [Shoko::Application::UseCases::Requests::TextInput],
                dictionary_query_backspace: [NilClass],
                dictionary_query_delete: [NilClass],
                submit_dictionary_query: [NilClass],
              }
            end
          end
        end
      end
    end
  end
end
