# frozen_string_literal: true

require_relative '../../../ports/inbound/menu_catalog'
require_relative '../../requests/mode_change'
require_relative '../../requests/selection_delta'
require_relative '../../requests/edit_op'
require_relative '../../support/intent_action_group'
require_relative '../../support/menu_session_access'
require_relative '../../support/text_editing'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          # Handles dictionary mode, query, and selection intents from the menu.
          class Dictionary
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess

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


            def open_dictionary_mode(mode)
              return open_dictionary_search_mode if mode == :dictionary_search

              reset_dictionary_mode
              @dictionary_workflow.fetch_dictionary_catalog
              :handled
            end

            def close_dictionary_mode(mode)
              target_mode = mode || (current_menu.mode == :dictionary_search ? :dictionary : :settings)
              update_menu(mode: target_mode)
              :handled
            end

            def submit_dictionary_query
              update_menu(mode: :dictionary, dictionary_selected: 0)
              :handled
            end

            def open_dictionary_search_mode
              query = current_menu.dictionary_query.to_s
              update_menu(mode: :dictionary_search, dictionary_cursor: query.length)
              :handled
            end

            def reset_dictionary_mode
              update_menu(dictionary_mode_payload)
            end

            def dictionary_mode_payload
              {
                mode: :dictionary,
                dictionary_selected: 0,
                dictionary_query: '',
                dictionary_cursor: 0,
                dictionary_results: [],
                dictionary_status: :idle,
                dictionary_message: '',
                dictionary_progress: 0.0,
              }
            end


            def update_query(operation, text = nil)
              menu = current_menu
              current = menu.dictionary_query.to_s
              cursor = (menu.dictionary_cursor || current.length).to_i
              next_text, next_cursor = Shoko::Application::UseCases::Support::TextEditing.apply_edit(
                current,
                cursor,
                operation,
                text: text
              )
              update_menu(dictionary_query: next_text, dictionary_cursor: next_cursor)
              :handled
            end

            def dictionary_filtered_results
              menu = current_menu
              query = menu.dictionary_query.to_s.downcase
              results = Array(menu.dictionary_results)
              return results if query.empty?

              results.select do |item|
                name = item[:name].to_s.downcase
                pair = "#{item[:source]}-#{item[:target]}".downcase
                name.include?(query) || pair.include?(query)
              end
            end

            def dictionary_action_count
              Shoko::Application::Ports::Inbound::MenuCatalog.dictionary_action_items.length
            end


            def move_dictionary_selection(delta)
              current = (current_menu.dictionary_selected || 0).to_i
              max_index = [dictionary_action_count + dictionary_filtered_results.length - 1, 0].max
              update_menu(dictionary_selected: (current + delta).clamp(0, max_index))
              :handled
            end

            def activate_dictionary_selection
              index = (current_menu.dictionary_selected || 0).to_i

              if index < dictionary_action_count
                handle_dictionary_action(index)
              else
                entry = dictionary_filtered_results[index - dictionary_action_count]
                @dictionary_workflow.download_dictionary(entry) if entry
              end

              :handled
            end

            def handle_dictionary_action(index)
              action = Shoko::Application::Ports::Inbound::MenuCatalog.dictionary_action_item(index)&.action

              case action
              when :dictionary_back
                close_dictionary_mode(:settings)
              when :toggle_dictionary_backend
                @settings_service.toggle_dictionary_backend
              when :cycle_dictionary_pair
                @settings_service.cycle_dictionary_pair
              when :dictionary_refresh
                @dictionary_workflow.fetch_dictionary_catalog
              end
            end

          end
        end
      end
    end
  end
end
