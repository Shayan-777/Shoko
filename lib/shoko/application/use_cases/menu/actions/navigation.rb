# frozen_string_literal: true

require_relative '../../../../shared/menu_definitions'
require_relative '../../requests/selection_delta'
require_relative 'navigation/mode_flow'
require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Navigation
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include ModeFlow

            SUPPORTED_INTENTS = %i[
              move_menu_selection_up
              move_menu_selection_down
              activate_menu_selection
              switch_to_menu_mode
              switch_to_browse_mode
              switch_to_search_mode
              open_annotations_mode
            ].freeze

            def initialize(menu_state_reader:, menu_session_mutator:, menu_runtime:, annotation_service:, logger: nil)
              @menu_state_reader = menu_state_reader
              @menu_session_mutator = menu_session_mutator
              @menu_runtime = menu_runtime
              @annotation_service = annotation_service
              @logger = logger
            end

            def call(intent, payload = nil)
              validate_payload!(intent, payload)

              case intent
              when :move_menu_selection_up
                move_main_menu(payload&.delta || -1)
              when :move_menu_selection_down
                move_main_menu(payload&.delta || 1)
              when :activate_menu_selection
                activate_main_menu_selection
              when :switch_to_menu_mode
                switch_mode(:menu)
              when :switch_to_browse_mode
                switch_browse_mode
              when :switch_to_search_mode
                switch_search_mode
              when :open_annotations_mode
                open_annotations_mode
              else
                raise ArgumentError, "unsupported menu navigation intent: #{intent}"
              end
            end

            private

            def supported_payloads
              {
                move_menu_selection_up: [Shoko::Application::UseCases::Requests::SelectionDelta],
                move_menu_selection_down: [Shoko::Application::UseCases::Requests::SelectionDelta],
                activate_menu_selection: [NilClass],
                switch_to_menu_mode: [NilClass],
                switch_to_browse_mode: [NilClass],
                switch_to_search_mode: [NilClass],
                open_annotations_mode: [NilClass],
              }
            end

            def move_main_menu(delta)
              current = (@menu_state_reader.selected || 0).to_i
              max_index = Shoko::Shared::MenuDefinitions.main_menu_items.length - 1
              @menu_session_mutator.update_menu(selected: (current + delta).clamp(0, max_index))
              :handled
            end

            def activate_main_menu_selection
              item = Shoko::Shared::MenuDefinitions.main_menu_item((@menu_state_reader.selected || 0).to_i)

              case item&.action
              when :switch_to_browse then switch_browse_mode
              when :switch_to_library then switch_mode(:library)
              when :switch_to_annotations then open_annotations_mode
              when :open_download then open_download_mode
              when :switch_to_settings then switch_mode(:settings)
              when :quit then quit_application
              else
                :pass
              end
            end
          end
        end
      end
    end
  end
end
