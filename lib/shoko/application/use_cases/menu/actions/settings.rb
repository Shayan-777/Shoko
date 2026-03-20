# frozen_string_literal: true

require_relative '../../../../shared/menu_definitions'
require_relative '../../requests/selection_delta'
require_relative 'settings/activation_flow'
require_relative '../../support/intent_action_group'
require_relative '../../support/menu_session_access'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          # Handles settings selection and activation intents from the menu.
          class Settings
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess
            include ActivationFlow

            SETTINGS_ACTIONS = Shoko::Shared::MenuDefinitions.settings_actions
            MOVE_INTENTS = %i[move_settings_selection_up move_settings_selection_down].freeze

            SUPPORTED_INTENTS = %i[
              move_settings_selection_up
              move_settings_selection_down
              activate_settings_selection
            ].freeze

            def initialize(menu_session_store:, settings_service:, catalog:, navigation_actions:, dictionary_actions:,
                           menu_transient_store: nil)
              assign_menu_session_store!(menu_session_store, menu_transient_store: menu_transient_store)
              @settings_service = settings_service
              @catalog = catalog
              @navigation_actions = navigation_actions
              @dictionary_actions = dictionary_actions
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported menu settings intent')
            end

            private

            def routes
              @routes ||= handled_routes(*MOVE_INTENTS, payload: :delta) { |delta| shift_settings_selection(delta) }
                          .merge(activate_settings_selection: route { activate_settings_selection })
                          .freeze
            end

            def supported_payloads
              delta_payloads(*MOVE_INTENTS).merge(nil_payloads(:activate_settings_selection))
            end

            def shift_settings_selection(delta)
              current = (current_menu.settings_selected || 0).to_i
              max_index = SETTINGS_ACTIONS.length - 1
              update_menu(settings_selected: (current + delta).clamp(0, max_index))
              :handled
            end
          end
        end
      end
    end
  end
end
