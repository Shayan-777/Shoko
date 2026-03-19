# frozen_string_literal: true

require_relative '../../requests/mode_change'
require_relative '../../requests/selection_delta'
require_relative '../../requests/text_input'
require_relative 'download/mode_flow'
require_relative 'download/query_flow'
require_relative 'download/source_flow'
require_relative '../../support/intent_action_group'
require_relative '../../support/menu_session_access'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          # Handles download mode, source selection, and query intents from the menu.
          class Download
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess
            include ModeFlow
            include QueryFlow
            include SourceFlow

            MODE_INTENTS = %i[
              open_download_mode
              close_download_mode
              close_download_source_mode
            ].freeze
            MOVE_RESULT_INTENTS = %i[
              move_download_selection_up
              move_download_selection_down
            ].freeze
            MOVE_SOURCE_INTENTS = %i[
              move_download_source_selection_up
              move_download_source_selection_down
            ].freeze
            SUPPORTED_INTENTS = %i[
              open_download_mode
              close_download_mode
              open_download_source_mode
              close_download_source_mode
              refresh_download_results
              move_download_selection_up
              move_download_selection_down
              move_download_source_selection_up
              move_download_source_selection_down
              activate_download_selection
              activate_download_source_selection
              download_query_insert_text
              download_query_backspace
              download_query_delete
              submit_download_query
              download_next_page
              download_prev_page
            ].freeze

            def initialize(menu_session_store:, menu_mode_control:, menu_download_selection:, download_workflow:,
                           settings_service:, app_config_store:, menu_transient_store: nil)
              assign_menu_session_store!(
                menu_session_store,
                menu_transient_store: menu_transient_store
              )
              @menu_mode_control = menu_mode_control
              @menu_download_selection = menu_download_selection
              @download_workflow = download_workflow
              @settings_service = settings_service
              @app_config_store = app_config_store
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported menu download intent')
            end

            private

            def routes
              @routes ||= mode_routes.merge(selection_routes).merge(query_routes).freeze
            end

            def supported_payloads
              mode_payloads(*MODE_INTENTS, allow_nil: true)
                .merge(delta_payloads(*MOVE_RESULT_INTENTS, *MOVE_SOURCE_INTENTS))
                .merge(query_payloads)
                .merge(selection_payloads)
            end

            def mode_routes
              {
                open_download_mode: route(payload: :mode) { |mode| open_download_mode(mode) },
                close_download_mode: route(payload: :mode) { |mode| close_download_mode(mode) },
                open_download_source_mode: route(result: :handled) { open_download_source_mode },
                close_download_source_mode: route(payload: :mode) { |mode| close_download_source_mode(mode) },
                refresh_download_results: route(result: :handled) { refresh_downloads },
              }
            end

            def selection_routes
              handled_routes(*MOVE_RESULT_INTENTS, payload: :delta) { |delta| move_download_selection(delta) }
                .merge(
                  handled_routes(*MOVE_SOURCE_INTENTS, payload: :delta) do |delta|
                    move_download_source_selection(delta)
                  end
                )
                .merge(
                  activate_download_selection: route(result: :handled) { activate_download_selection },
                  activate_download_source_selection: route(result: :handled) { activate_download_source_selection }
                )
            end

            def query_routes
              {
                download_query_insert_text: route(payload: :text) { |text| update_query(:insert, text) },
                download_query_backspace: route(result: :handled) { update_query(:backspace) },
                download_query_delete: route(result: :handled) { update_query(:delete) },
                submit_download_query: route { submit_download_query },
                download_next_page: route { open_page(current_menu.download_next) },
                download_prev_page: route { open_page(current_menu.download_prev) },
              }
            end

            def query_payloads
              text_payloads(:download_query_insert_text).merge(
                nil_payloads(
                  :download_query_backspace,
                  :download_query_delete,
                  :submit_download_query,
                  :download_next_page,
                  :download_prev_page
                )
              )
            end

            def selection_payloads
              nil_payloads(
                :open_download_source_mode,
                :refresh_download_results,
                :activate_download_selection,
                :activate_download_source_selection
              )
            end
          end
        end
      end
    end
  end
end
