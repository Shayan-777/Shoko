# frozen_string_literal: true

require_relative '../../../ports/inbound/menu_catalog'
require_relative '../../requests/selection_delta'
require_relative 'navigation/mode_flow'
require_relative '../../support/intent_action_group'
require_relative '../../support/menu_session_access'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          # Handles top-level menu navigation and mode-switching intents.
          class Navigation
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess
            include ModeFlow

            MOVE_INTENTS = %i[move_menu_selection_up move_menu_selection_down].freeze
            SUPPORTED_INTENTS = %i[
              move_menu_selection_up
              move_menu_selection_down
              activate_menu_selection
              switch_to_menu_mode
              switch_to_browse_mode
              switch_to_search_mode
              open_annotations_mode
              open_rss_reader_mode
              close_rss_reader_mode
            ].freeze

            def initialize(menu_session_store:, menu_mode_control:, application_exit_control:, annotation_service:,
                           translator_workflow:, rss_reader_workflow:,
                           menu_transient_store:, logger: nil)
              assign_menu_session_store!(menu_session_store, menu_transient_store: menu_transient_store)
              @menu_mode_control = menu_mode_control
              @application_exit_control = application_exit_control
              @annotation_service = annotation_service
              @translator_workflow = translator_workflow
              @rss_reader_workflow = rss_reader_workflow
              @logger = logger
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported menu navigation intent')
            end

            private

            def routes
              @routes ||= movement_routes.merge(mode_routes).merge(activation_routes).freeze
            end

            def supported_payloads
              delta_payloads(*MOVE_INTENTS)
                .merge(
                  nil_payloads(
                    :activate_menu_selection,
                    :switch_to_menu_mode,
                    :switch_to_browse_mode,
                    :switch_to_search_mode,
                    :open_annotations_mode,
                    :open_rss_reader_mode
                  )
                )
                .merge(mode_payloads(:close_rss_reader_mode, allow_nil: true))
            end

            def movement_routes
              handled_routes(*MOVE_INTENTS, payload: :delta) { |delta| move_main_menu(delta) }
            end

            def mode_routes
              handled_routes(:switch_to_menu_mode) { switch_mode(:menu) }
                .merge(handled_routes(:switch_to_browse_mode) { switch_browse_mode })
                .merge(handled_routes(:switch_to_search_mode) { switch_search_mode })
                .merge(handled_routes(:open_annotations_mode) { open_annotations_mode })
                .merge(handled_routes(:open_rss_reader_mode) { open_rss_reader_mode })
                .merge(close_rss_reader_mode: route(payload: :mode) { |mode| close_rss_reader_mode(mode) })
            end

            def activation_routes
              { activate_menu_selection: route { activate_main_menu_selection } }
            end

            def move_main_menu(delta)
              current = (current_menu.selected || 0).to_i
              max_index = Shoko::Application::Ports::Inbound::MenuCatalog.main_menu_items.length - 1
              update_menu(selected: (current + delta).clamp(0, max_index))
              :handled
            end

            def activate_main_menu_selection
              item = Shoko::Application::Ports::Inbound::MenuCatalog.main_menu_item((current_menu.selected || 0).to_i)
              dispatch_main_menu_action(item&.action)
            end

            def open_library_mode
              switch_mode(:library)
            end

            def open_settings_mode
              switch_mode(:settings)
            end

            def dispatch_main_menu_action(action)
              handler = main_menu_action_handlers[action]
              return :pass unless handler

              handler.call
            end

            def main_menu_action_handlers
              @main_menu_action_handlers ||= {
                switch_to_browse: -> { switch_browse_mode },
                switch_to_library: -> { open_library_mode },
                switch_to_annotations: -> { open_annotations_mode },
                open_rss_reader: -> { open_rss_reader_mode },
                open_download: -> { open_download_mode },
                open_translator: -> { open_translator_mode },
                switch_to_settings: -> { open_settings_mode },
                quit: -> { quit_application },
              }
            end
          end
        end
      end
    end
  end
end
