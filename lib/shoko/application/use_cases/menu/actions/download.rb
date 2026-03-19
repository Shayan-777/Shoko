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
          class Download
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess
            include ModeFlow
            include QueryFlow
            include SourceFlow

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
              @routes ||= {
                open_download_mode: route(payload: :mode) { |mode| open_download_mode(mode) },
                close_download_mode: route(payload: :mode) { |mode| close_download_mode(mode) },
                open_download_source_mode: route(result: :handled) { open_download_source_mode },
                close_download_source_mode: route(payload: :mode) { |mode| close_download_source_mode(mode) },
                refresh_download_results: route(result: :handled) { refresh_downloads },
                move_download_selection_up: route(payload: :delta) { |delta| move_download_selection(delta) },
                move_download_selection_down: route(payload: :delta) { |delta| move_download_selection(delta) },
                move_download_source_selection_up: route(payload: :delta) do |delta|
                  move_download_source_selection(delta)
                end,
                move_download_source_selection_down: route(payload: :delta) do |delta|
                  move_download_source_selection(delta)
                end,
                activate_download_selection: route(result: :handled) { activate_download_selection },
                activate_download_source_selection: route(result: :handled) { activate_download_source_selection },
                download_query_insert_text: route(payload: :text) { |text| update_query(:insert, text) },
                download_query_backspace: route(result: :handled) { update_query(:backspace) },
                download_query_delete: route(result: :handled) { update_query(:delete) },
                submit_download_query: route { submit_download_query },
                download_next_page: route { open_page(current_menu.download_next) },
                download_prev_page: route { open_page(current_menu.download_prev) },
              }.freeze
            end

            def supported_payloads
              {
                open_download_mode: [Shoko::Application::UseCases::Requests::ModeChange, NilClass],
                close_download_mode: [Shoko::Application::UseCases::Requests::ModeChange, NilClass],
                open_download_source_mode: [NilClass],
                close_download_source_mode: [Shoko::Application::UseCases::Requests::ModeChange, NilClass],
                refresh_download_results: [NilClass],
                move_download_selection_up: [Shoko::Application::UseCases::Requests::SelectionDelta],
                move_download_selection_down: [Shoko::Application::UseCases::Requests::SelectionDelta],
                move_download_source_selection_up: [Shoko::Application::UseCases::Requests::SelectionDelta],
                move_download_source_selection_down: [Shoko::Application::UseCases::Requests::SelectionDelta],
                activate_download_selection: [NilClass],
                activate_download_source_selection: [NilClass],
                download_query_insert_text: [Shoko::Application::UseCases::Requests::TextInput],
                download_query_backspace: [NilClass],
                download_query_delete: [NilClass],
                submit_download_query: [NilClass],
                download_next_page: [NilClass],
                download_prev_page: [NilClass],
              }
            end
          end
        end
      end
    end
  end
end
