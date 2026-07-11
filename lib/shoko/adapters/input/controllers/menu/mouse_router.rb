# frozen_string_literal: true

require 'shoko/application/use_cases/requests/selection_delta'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Routes menu mouse events against the per-frame hit registry the
          # components populate while rendering: rail entries navigate, list
          # rows select (and a click on the already-selected row activates,
          # exactly like ENTER), wheel turns move the focused list, and
          # pointer motion drives hover highlights. Every action dispatches
          # the same intents the keyboard uses, so mouse and keys can never
          # drift apart.
          class MouseRouter
            WHEEL_UP = 64
            WHEEL_DOWN = 65
            MOTION_BUTTON_MASK = 32

            # list key -> [move-up intent, move-down intent] for wheel turns.
            WHEEL_INTENTS = {
              browse: %i[move_browse_selection_up move_browse_selection_down],
              library: %i[move_library_selection_up move_library_selection_down],
              settings: %i[move_settings_selection_up move_settings_selection_down],
              dictionary: %i[move_dictionary_selection_up move_dictionary_selection_down],
              translator_packs: %i[move_translator_packs_selection_up move_translator_packs_selection_down],
              download: %i[move_download_selection_up move_download_selection_down],
              download_source: %i[move_download_source_selection_up move_download_source_selection_down],
              annotations: %i[move_annotation_selection_up move_annotation_selection_down],
              rss_feeds: %i[rss_reader_move_up rss_reader_move_down],
              rss_articles: %i[rss_reader_move_up rss_reader_move_down],
              rss_reading: %i[rss_reader_move_up rss_reader_move_down],
              translator_language: %i[move_translator_language_selection_up
                                      move_translator_language_selection_down],
            }.freeze

            # list key -> the activation intent its ENTER binding dispatches.
            ACTIVATE_INTENTS = {
              browse: :open_selected_book,
              library: :activate_library_selection,
              settings: :activate_settings_selection,
              dictionary: :activate_dictionary_selection,
              translator_packs: :activate_translator_packs_selection,
              download: :activate_download_selection,
              download_source: :activate_download_source_selection,
              annotations: :activate_annotation_selection,
              rss_feeds: :rss_reader_activate_selection,
              rss_articles: :rss_reader_activate_selection,
            }.freeze

            # list key -> the cursor field a first click selects through.
            CURSOR_FIELDS = {
              browse: :browse_selected,
              library: :library_selected,
              settings: :settings_selected,
              dictionary: :dictionary_selected,
              translator_packs: :translator_packs_selected,
              download: :download_selected,
              download_source: :download_source_selected,
            }.freeze

            def initialize(hit_registry:, menu_state_reader:, menu_session_mutator:,
                           intent_handler:, main_menu_component:)
              @hit_registry = hit_registry
              @menu_state_reader = menu_state_reader
              @menu_session_mutator = menu_session_mutator
              @intent_handler = intent_handler
              @main_menu_component = main_menu_component
            end

            # Returns true when the event was consumed (menu mouse events
            # always are — stray tokens must never leak into key handling).
            def handle(event)
              return false unless event && @hit_registry

              col = event[:x].to_i + 1
              row = event[:y].to_i + 1
              @hit_registry.pointer_moved(col, row)
              route(event, col, row)
              true
            end

            private

            def route(event, col, row)
              return route_wheel(event, col, row) if wheel?(event)
              return unless left_release?(event)

              action = @hit_registry.hit(col, row)
              route_click(action) if action
            end

            def wheel?(event)
              [WHEEL_UP, WHEEL_DOWN].include?(event[:button].to_i & ~MOTION_BUTTON_MASK)
            end

            def left_release?(event)
              event[:released] && event[:button].to_i.nobits?(0b11)
            end

            def route_wheel(event, col, row)
              action = @hit_registry.hit(col, row)
              return unless action

              delta = (event[:button].to_i & ~MOTION_BUTTON_MASK) == WHEEL_UP ? -1 : 1
              return wheel_rail(delta) if %i[rail_surface rail].include?(action[:type])

              intents = WHEEL_INTENTS[action[:list]]
              return unless intents

              dispatch(delta.negative? ? intents.first : intents.last, selection_delta(delta))
            end

            # Wheel over the rail flips the landing selection (and with it the
            # live preview); inside a view the rail stays still under the wheel.
            def wheel_rail(delta)
              return unless current_mode == :menu

              intent = delta.negative? ? :move_menu_selection_up : :move_menu_selection_down
              dispatch(intent, selection_delta(delta))
            end

            def route_click(action)
              case action[:type]
              when :rail then click_rail(action[:index])
              when :list_row then click_list_row(action[:list], action[:index])
              end
            end

            # On the landing screen the first click previews an entry and a
            # second click opens it; inside a view a rail click jumps straight
            # to the clicked entry, like any application sidebar.
            def click_rail(index)
              if current_mode == :menu
                return dispatch(:activate_menu_selection) if index == current_selected

                update_menu(selected: index)
              else
                update_menu(selected: index)
                dispatch(:activate_menu_selection)
              end
            end

            # First click moves the selection; a click on the already-selected
            # row activates it — ENTER, spelled with the pointer.
            def click_list_row(list, index)
              return click_annotation_row(index) if list == :annotations
              return click_rss_row(list, index) if %i[rss_feeds rss_articles].include?(list)

              field = CURSOR_FIELDS[list]
              return unless field

              return dispatch(ACTIVATE_INTENTS[list]) if current_cursor(field) == index

              update_menu(field => index)
            end

            def click_annotation_row(index)
              screen = @main_menu_component.annotations_screen
              return unless screen

              return dispatch(ACTIVATE_INTENTS[:annotations]) if screen.selected == index

              screen.selected = index
            end

            def click_rss_row(list, index)
              if list == :rss_feeds
                click_rss_entry(:rss_feeds, index, key_field: :key, state_field: :rss_selected_feed_key)
              else
                click_rss_entry(:rss_articles, index, key_field: :id, state_field: :rss_selected_article_id)
              end
            end

            def click_rss_entry(list, index, key_field:, state_field:)
              entries = Array(@menu_state_reader.public_send(list))
              entry = entries[index]
              return unless entry

              value = entry[key_field].to_s
              return dispatch(ACTIVATE_INTENTS[list]) if @menu_state_reader.public_send(state_field).to_s == value

              update_menu(state_field => value)
            end

            def current_mode
              (@menu_state_reader.mode || :menu).to_sym
            end

            def current_selected
              (@menu_state_reader.selected || 0).to_i
            end

            def current_cursor(field)
              (@menu_state_reader.public_send(field) || 0).to_i
            end

            def dispatch(intent, payload = nil)
              @intent_handler.handle_menu_intent(intent, payload)
            end

            def update_menu(payload)
              @menu_session_mutator.update_menu(payload)
            end

            def selection_delta(delta)
              Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: delta)
            end
          end
        end
      end
    end
  end
end
