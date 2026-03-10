# frozen_string_literal: true

require_relative '../../requests/mode_change'
require_relative '../../requests/selection_delta'
require_relative '../../requests/text_input'
require_relative 'download/mode_flow'
require_relative 'download/query_flow'
require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Download
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include ModeFlow
            include QueryFlow

            SUPPORTED_INTENTS = %i[
              open_download_mode
              close_download_mode
              refresh_download_results
              move_download_selection_up
              move_download_selection_down
              activate_download_selection
              download_query_insert_text
              download_query_backspace
              download_query_delete
              submit_download_query
              download_next_page
              download_prev_page
            ].freeze

            def initialize(menu_state_reader:, menu_session_mutator:, menu_runtime:, download_workflow:)
              @menu_state_reader = menu_state_reader
              @menu_session_mutator = menu_session_mutator
              @menu_runtime = menu_runtime
              @download_workflow = download_workflow
            end

            def call(intent, payload = nil)
              case intent
              when :open_download_mode
                open_download_mode(mode_from(payload, intent))
              when :close_download_mode
                close_download_mode(mode_from(payload, intent))
              when :refresh_download_results
                validate_payload!(intent, payload)
                refresh_downloads
              when :move_download_selection_up
                move_download_selection(positive_delta(payload, intent))
              when :move_download_selection_down
                move_download_selection(positive_delta(payload, intent))
              when :activate_download_selection
                validate_payload!(intent, payload)
                activate_download_selection
              when :download_query_insert_text
                update_query(:insert, text_from(payload, intent))
              when :download_query_backspace
                validate_payload!(intent, payload)
                update_query(:backspace)
              when :download_query_delete
                validate_payload!(intent, payload)
                update_query(:delete)
              when :submit_download_query
                validate_payload!(intent, payload)
                submit_download_query
              when :download_next_page
                validate_payload!(intent, payload)
                open_page(@menu_state_reader.download_next)
              when :download_prev_page
                validate_payload!(intent, payload)
                open_page(@menu_state_reader.download_prev)
              else
                raise ArgumentError, "unsupported menu download intent: #{intent}"
              end
            end

            private

            def supported_payloads
              {
                open_download_mode: [Shoko::Application::UseCases::Requests::ModeChange, NilClass],
                close_download_mode: [Shoko::Application::UseCases::Requests::ModeChange, NilClass],
                refresh_download_results: [NilClass],
                move_download_selection_up: [Shoko::Application::UseCases::Requests::SelectionDelta],
                move_download_selection_down: [Shoko::Application::UseCases::Requests::SelectionDelta],
                activate_download_selection: [NilClass],
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
