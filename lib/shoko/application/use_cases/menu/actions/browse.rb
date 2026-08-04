# frozen_string_literal: true

require_relative '../../requests/selection_delta'
require_relative '../../support/intent_action_group'
require_relative '../../support/menu_session_access'
require 'shoko/core/services/prepagination_status'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          # Handles menu browse and library selection intents.
          class Browse
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess

            BROWSE_MOVE_INTENTS = %i[move_browse_selection_up move_browse_selection_down].freeze
            LIBRARY_MOVE_INTENTS = %i[move_library_selection_up move_library_selection_down].freeze
            SUPPORTED_INTENTS = %i[
              move_browse_selection_up
              move_browse_selection_down
              open_selected_book
              move_library_selection_up
              move_library_selection_down
              activate_library_selection
              toggle_library_details
            ].freeze

            def initialize(menu_session_store:, menu_browse_inspection:, reader_launch_service:,
                           menu_transient_store:)
              assign_menu_session_store!(menu_session_store, menu_transient_store: menu_transient_store)
              @menu_browse_inspection = menu_browse_inspection
              @reader_launch_service = reader_launch_service
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported menu browse intent')
            end

            private

            def routes
              @routes ||= browse_routes.merge(library_routes).merge(toggle_routes).freeze
            end

            def supported_payloads
              delta_payloads(*BROWSE_MOVE_INTENTS, *LIBRARY_MOVE_INTENTS)
                .merge(nil_payloads(:open_selected_book, :activate_library_selection, :toggle_library_details))
            end

            def browse_routes
              handled_routes(*BROWSE_MOVE_INTENTS, payload: :delta) { |delta| move_browse_selection(delta) }
                .merge(open_selected_book: route(result: :handled) { @reader_launch_service.open_selected_book })
            end

            def library_routes
              handled_routes(*LIBRARY_MOVE_INTENTS, payload: :delta) { |delta| move_library_selection(delta) }
                .merge(activate_library_selection: route { activate_library_selection })
            end

            def toggle_routes
              { toggle_library_details: route(result: :handled) { toggle_library_details } }
            end

            def move_browse_selection(delta)
              max_index = [@menu_browse_inspection.browse_item_count.to_i - 1, 0].max
              current = (current_menu.browse_selected || 0).to_i
              update_menu(browse_selected: (current + delta).clamp(0, max_index))
              :handled
            end

            def move_library_selection(delta)
              max_index = [@menu_browse_inspection.library_item_count.to_i - 1, 0].max
              current = (current_menu.library_selected || 0).to_i
              update_menu(library_selected: (current + delta).clamp(0, max_index))
              :handled
            end

            def activate_library_selection
              target_path = @menu_browse_inspection.selected_library_path
              return @reader_launch_service.file_not_found unless target_path
              # A book still queued for, or in the middle of, recalculation isn't
              # ready to open. Consume the keypress (the row's "queued"/
              # "recalculating" marker explains the no-op) rather than opening a
              # book whose pages are mid-rebuild.
              return :handled unless library_selection_openable?

              @reader_launch_service.run_reader(target_path)
              :handled
            end

            def library_selection_openable?
              menu = current_menu
              status = Shoko::Core::Services::PrepaginationStatus.for_path(
                @menu_browse_inspection.selected_library_source_path,
                paths: menu.prepaginate_paths,
                done: menu.prepaginate_done,
                active: menu.prepaginate_active == true
              )
              Shoko::Core::Services::PrepaginationStatus.openable?(status)
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
