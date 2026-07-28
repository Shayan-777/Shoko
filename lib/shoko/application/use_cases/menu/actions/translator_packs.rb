# frozen_string_literal: true

require 'shoko/application/ports/inbound/menu_catalog'
require_relative '../../requests/mode_change'
require_relative '../../requests/selection_delta'
require_relative '../../requests/edit_op'
require_relative '../../support/intent_action_group'
require_relative '../../support/menu_session_access'
require_relative '../../support/text_editing'
require 'shoko/core/services/translator_pack_filter'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          # Handles the translator language-pack screen: mode, catalog list
          # selection, pack download/removal, filter query, and the backend
          # toggle row.
          class TranslatorPacks
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess

            MODE_INTENTS = %i[open_translator_packs_mode close_translator_packs_mode].freeze
            MOVE_INTENTS = %i[move_translator_packs_selection_up move_translator_packs_selection_down].freeze
            SUPPORTED_INTENTS = %i[
              open_translator_packs_mode
              close_translator_packs_mode
              refresh_translator_packs
              move_translator_packs_selection_up
              move_translator_packs_selection_down
              activate_translator_packs_selection
              edit_translator_packs_query
              submit_translator_packs_query
            ].freeze

            def initialize(menu_session_store:, translator_packs_workflow:, settings_service:,
                           menu_transient_store:)
              assign_menu_session_store!(menu_session_store, menu_transient_store: menu_transient_store)
              @translator_packs_workflow = translator_packs_workflow
              @settings_service = settings_service
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported menu translator packs intent')
            end

            private

            def routes
              @routes ||= mode_routes.merge(selection_routes).merge(query_routes).freeze
            end

            def supported_payloads
              mode_payloads(*MODE_INTENTS, allow_nil: true)
                .merge(delta_payloads(*MOVE_INTENTS))
                .merge(edit_op_payloads(:edit_translator_packs_query))
                .merge(
                  nil_payloads(
                    :refresh_translator_packs,
                    :activate_translator_packs_selection,
                    :submit_translator_packs_query
                  )
                )
            end

            def mode_routes
              {
                open_translator_packs_mode: route(payload: :mode) { |mode| open_packs_mode(mode) },
                close_translator_packs_mode: route(payload: :mode) { |mode| close_packs_mode(mode) },
                refresh_translator_packs: route(result: :handled) do
                  @translator_packs_workflow.fetch_pack_catalog
                end,
              }
            end

            def selection_routes
              handled_routes(*MOVE_INTENTS, payload: :delta) { |delta| move_selection(delta) }
                .merge(activate_translator_packs_selection: route(result: :handled) { activate_selection })
            end

            def query_routes
              {
                edit_translator_packs_query: route(payload: :edit_op, result: :handled) do |op|
                  update_query(op.operation, op.text)
                end,
                submit_translator_packs_query: route(result: :handled) { submit_query },
              }
            end

            def open_packs_mode(mode)
              return open_search_mode if mode == :translator_packs_search

              update_menu(packs_mode_payload)
              @translator_packs_workflow.fetch_pack_catalog
              :handled
            end

            def close_packs_mode(mode)
              target_mode = mode || (current_menu.mode == :translator_packs_search ? :translator_packs : :settings)
              update_menu(mode: target_mode)
              :handled
            end

            def submit_query
              update_menu(mode: :translator_packs, translator_packs_selected: 0)
              :handled
            end

            def open_search_mode
              query = current_menu.translator_packs_query.to_s
              update_menu(mode: :translator_packs_search, translator_packs_cursor: query.length)
              :handled
            end

            def packs_mode_payload
              {
                mode: :translator_packs,
                translator_packs_selected: 0,
                translator_packs_query: '',
                translator_packs_cursor: 0,
                translator_packs_status: :idle,
                translator_packs_message: '',
                translator_packs_progress: 0.0,
                translator_packs_pending_remove: nil,
              }
            end

            def update_query(operation, text = nil)
              menu = current_menu
              current = menu.translator_packs_query.to_s
              cursor = (menu.translator_packs_cursor || current.length).to_i
              next_text, next_cursor = Shoko::Application::UseCases::Support::TextEditing.apply_edit(
                current,
                cursor,
                operation,
                text: text
              )
              update_menu(translator_packs_query: next_text, translator_packs_cursor: next_cursor)
              :handled
            end

            def filtered_results
              menu = current_menu
              query = menu.translator_packs_query.to_s.downcase
              Shoko::Core::Services::TranslatorPackFilter.call(menu.translator_packs_results, query)
            end

            def action_count
              Shoko::Application::Ports::Inbound::MenuCatalog.translator_packs_action_items.length
            end

            def move_selection(delta)
              current = (current_menu.translator_packs_selected || 0).to_i
              max_index = [action_count + filtered_results.length - 1, 0].max
              update_menu(
                translator_packs_selected: (current + delta).clamp(0, max_index),
                translator_packs_pending_remove: nil
              )
              :handled
            end

            def activate_selection
              return :handled if pack_operation_busy?

              index = (current_menu.translator_packs_selected || 0).to_i

              if index < action_count
                handle_action(index)
              else
                entry = filtered_results[index - action_count]
                activate_pack(entry) if entry
              end

              :handled
            end

            def pack_operation_busy?
              %i[loading downloading].include?((current_menu.translator_packs_status || :idle).to_sym)
            end

            def activate_pack(entry)
              pair = "#{entry[:from]}-#{entry[:to]}"
              return confirm_pack_removal(entry, pair) if entry[:installed] && !entry[:update_available]

              update_menu(translator_packs_pending_remove: nil)
              @translator_packs_workflow.download_pack(entry)
            end

            def confirm_pack_removal(entry, pair)
              if current_menu.translator_packs_pending_remove.to_s == pair
                update_menu(translator_packs_pending_remove: nil)
                @translator_packs_workflow.download_pack(entry)
              else
                update_menu(
                  translator_packs_pending_remove: pair,
                  translator_packs_message: "Press Enter again to remove #{entry[:from]} → #{entry[:to]}"
                )
              end
            end

            def handle_action(index)
              action = Shoko::Application::Ports::Inbound::MenuCatalog.translator_packs_action_item(index)&.action

              case action
              when :translator_packs_back
                close_packs_mode(:settings)
              when :toggle_translator_backend
                @settings_service.toggle_translator_backend
              when :translator_packs_refresh
                @translator_packs_workflow.fetch_pack_catalog
              end
            end
          end
        end
      end
    end
  end
end
