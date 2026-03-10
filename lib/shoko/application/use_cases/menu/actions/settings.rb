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
          class Settings
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess
            include ActivationFlow

            SETTINGS_ACTIONS = Shoko::Shared::MenuDefinitions.settings_actions

            SUPPORTED_INTENTS = %i[
              move_settings_selection_up
              move_settings_selection_down
              activate_settings_selection
            ].freeze

            def initialize(menu_session_store:, settings_service:, catalog:, navigation_actions:, dictionary_actions:)
              assign_menu_session_store!(menu_session_store)
              @settings_service = settings_service
              @catalog = catalog
              @navigation_actions = navigation_actions
              @dictionary_actions = dictionary_actions
            end

            def call(intent, payload = nil)
              validate_payload!(intent, payload)

              case intent
              when :move_settings_selection_up
                shift_settings_selection(payload&.delta || -1)
              when :move_settings_selection_down
                shift_settings_selection(payload&.delta || 1)
              when :activate_settings_selection
                activate_settings_selection
              else
                raise ArgumentError, "unsupported menu settings intent: #{intent}"
              end
            end

            private

            def supported_payloads
              {
                move_settings_selection_up: [Shoko::Application::UseCases::Requests::SelectionDelta],
                move_settings_selection_down: [Shoko::Application::UseCases::Requests::SelectionDelta],
                activate_settings_selection: [NilClass],
              }
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
