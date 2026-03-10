# frozen_string_literal: true

require_relative '../../requests/selection_delta'
require_relative '../../support/intent_action_group'
require_relative '../../support/menu_session_access'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Browse
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess

            SUPPORTED_INTENTS = %i[
              move_browse_selection_up
              move_browse_selection_down
              open_selected_book
              move_library_selection_up
              move_library_selection_down
              activate_library_selection
              toggle_library_details
            ].freeze

            def initialize(menu_session_store:, menu_browse_inspection:, reader_launch_service:)
              assign_menu_session_store!(menu_session_store)
              @menu_browse_inspection = menu_browse_inspection
              @reader_launch_service = reader_launch_service
            end

            def call(intent, payload = nil)
              validate_payload!(intent, payload)

              case intent
              when :move_browse_selection_up
                move_browse_selection(payload&.delta || -1)
              when :move_browse_selection_down
                move_browse_selection(payload&.delta || 1)
              when :open_selected_book
                @reader_launch_service.open_selected_book
                :handled
              when :move_library_selection_up
                move_library_selection(payload&.delta || -1)
              when :move_library_selection_down
                move_library_selection(payload&.delta || 1)
              when :activate_library_selection
                activate_library_selection
              when :toggle_library_details
                toggle_library_details
              else
                raise ArgumentError, "unsupported menu browse intent: #{intent}"
              end
            end

            private

            def supported_payloads
              {
                move_browse_selection_up: [Shoko::Application::UseCases::Requests::SelectionDelta],
                move_browse_selection_down: [Shoko::Application::UseCases::Requests::SelectionDelta],
                open_selected_book: [NilClass],
                move_library_selection_up: [Shoko::Application::UseCases::Requests::SelectionDelta],
                move_library_selection_down: [Shoko::Application::UseCases::Requests::SelectionDelta],
                activate_library_selection: [NilClass],
                toggle_library_details: [NilClass],
              }
            end

            def move_browse_selection(delta)
              max_index = [@menu_browse_inspection.browse_item_count.to_i - 1, 0].max
              current = (current_menu.browse_selected || 0).to_i
              update_menu(browse_selected: (current + delta).clamp(0, max_index))
              :handled
            end

            def move_library_selection(delta)
              max_index = [@menu_browse_inspection.library_item_count.to_i - 1, 0].max
              current = (current_menu.browse_selected || 0).to_i
              update_menu(browse_selected: (current + delta).clamp(0, max_index))
              :handled
            end

            def activate_library_selection
              target_path = @menu_browse_inspection.selected_library_path
              return @reader_launch_service.file_not_found unless target_path

              @reader_launch_service.run_reader(target_path)
              :handled
            end

            def toggle_library_details
              update_menu(library_details_open: !current_menu.library_details_open?)
              :handled
            end
          end
        end
      end
    end
  end
end
