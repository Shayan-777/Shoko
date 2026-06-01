# frozen_string_literal: true

require_relative '../../requests/mode_change'
require_relative '../../requests/selection_delta'
require_relative '../../requests/edit_op'
require_relative '../../support/intent_action_group'
require_relative '../../support/menu_session_access'
require_relative '../../../../shared/download_source_policy'
require_relative '../../support/text_editing'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          # Handles download mode, source selection, and query intents from the menu.
          class Download
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess

            MODE_INTENTS = %i[open_download_mode close_download_mode close_download_source_mode].freeze
            MOVE_RESULT_INTENTS = %i[move_download_selection_up move_download_selection_down].freeze
            MOVE_SOURCE_INTENTS = %i[move_download_source_selection_up move_download_source_selection_down].freeze
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
              edit_download_query
              submit_download_query
              download_next_page
              download_prev_page
            ].freeze

            def initialize(menu_session_store:, menu_download_selection:, download_workflow:,
                           settings_service:, app_config_store:, menu_transient_store:)
              assign_menu_session_store!(menu_session_store, menu_transient_store: menu_transient_store)
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
                edit_download_query: route(payload: :edit_op, result: :handled) do |op|
                  update_query(op.operation, op.text)
                end,
                submit_download_query: route { submit_download_query },
                download_next_page: route { open_page(current_menu.download_next) },
                download_prev_page: route { open_page(current_menu.download_prev) },
              }
            end

            def query_payloads
              edit_op_payloads(:edit_download_query).merge(
                nil_payloads(
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


            def open_download_mode(mode)
              return open_download_search_mode if mode == :download_search

              update_menu(download_mode_payload)
              :handled
            end

            def close_download_mode(mode)
              target_mode = mode || (current_menu.mode == :download_search ? :download : :menu)
              update_menu(mode: target_mode)
              :handled
            end

            def download_config
              @app_config_store.load
            end

            def open_download_search_mode
              query = current_menu.download_query.to_s
              update_menu(mode: :download_search, download_cursor: query.length)
              :handled
            end

            def download_mode_payload
              {
                mode: :download,
                download_query: '',
                download_cursor: 0,
                download_source_selected: current_download_source_index,
                download_selected: 0,
                download_results: [],
                download_count: 0,
                download_next: nil,
                download_prev: nil,
                download_status: :idle,
                download_message: '',
                download_progress: 0.0,
              }
            end

            def refresh_downloads
              query = current_menu.download_query.to_s
              @download_workflow.search_downloads(query: query)
              :handled
            end

            def move_download_selection(delta)
              menu = current_menu
              current = (menu.download_selected || 0).to_i
              max_index = [Array(menu.download_results).length - 1, 0].max
              update_menu(download_selected: (current + delta).clamp(0, max_index))
              :handled
            end

            def activate_download_selection
              book = @menu_download_selection.selected_download_result
              @download_workflow.download_book(book) if book
              :handled
            end

            def submit_download_query
              query = current_menu.download_query.to_s
              @download_workflow.search_downloads(query: query)
              close_download_mode(:download)
            end

            def open_page(page_url)
              return :pass unless page_url

              query = current_menu.download_query.to_s
              @download_workflow.search_downloads(query: query, page_url: page_url)
              :handled
            end

            def update_query(operation, text = nil)
              menu = current_menu
              current = menu.download_query.to_s
              cursor = (menu.download_cursor || current.length).to_i
              next_text, next_cursor = Shoko::Application::UseCases::Support::TextEditing.apply_edit(
                current,
                cursor,
                operation,
                text: text
              )
              update_menu(download_query: next_text, download_cursor: next_cursor)
              :handled
            end


            def open_download_source_mode
              update_menu(mode: :download_source_select, download_source_selected: current_download_source_index)
              :handled
            end

            def close_download_source_mode(mode)
              target_mode = mode || :download
              update_menu(mode: target_mode)
              :handled
            end

            def move_download_source_selection(delta)
              current = (current_menu.download_source_selected || current_download_source_index).to_i
              max_index = source_options.length - 1
              update_menu(download_source_selected: (current + delta).clamp(0, max_index))
              :handled
            end

            def activate_download_source_selection
              selected_source = source_options.fetch(selected_download_source_index, current_download_source)
              @settings_service.select_download_source(selected_source)
              reopen_download_mode
              refresh_or_reset_download_results(selected_source)
              :handled
            end

            def reopen_download_mode
              update_menu(mode: :download, download_source_selected: selected_download_source_index)
            end

            def refresh_or_reset_download_results(selected_source)
              query = current_menu.download_query.to_s.strip
              return reset_download_results(selected_source) if query.empty?

              @download_workflow.search_downloads(query: query)
            end

            def reset_download_results(selected_source)
              update_menu(
                download_results: [],
                download_count: 0,
                download_next: nil,
                download_prev: nil,
                download_selected: 0,
                download_status: :done,
                download_message: "Download source set to #{download_source_label(selected_source)}",
                download_progress: 0.0
              )
            end

            def selected_download_source_index
              max_index = source_options.length - 1
              (current_menu.download_source_selected || current_download_source_index).to_i.clamp(0, max_index)
            end

            def current_download_source_index
              source_options.index(current_download_source) || 0
            end

            def current_download_source
              Shoko::Shared::DownloadSourcePolicy.normalize(config_snapshot.download_source) ||
                Shoko::Shared::DownloadSourcePolicy.default_id
            end

            def config_snapshot
              @app_config_store.load
            end

            def source_options
              Shoko::Shared::DownloadSourcePolicy.canonical_ids
            end

            def download_source_label(source)
              Shoko::Shared::DownloadSourcePolicy.label_for(source)
            end

          end
        end
      end
    end
  end
end
