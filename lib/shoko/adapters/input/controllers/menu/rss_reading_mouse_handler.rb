# frozen_string_literal: true

require 'shoko/shared/index_range'
require 'shoko/shared/hash_normalizer'
require 'shoko/shared/terminal/mouse_button'
require 'shoko/shared/terminal/coordinates'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Drives text interaction in the RSS reading pane: drag to select,
          # right-click for the actions menu over the selection.
          #
          # The same gestures the book reader answers to, in the menu's own
          # runtime. Screen geometry comes from the reading screen, which knows
          # where each character was drawn; this handler only decides what a
          # gesture means and writes the result to menu state.
          class RssReadingMouseHandler
            def initialize(menu_state_reader:, menu_session_mutator:, intent_handler:, rss_reader_screen:)
              @menu_state_reader = menu_state_reader
              @menu_session_mutator = menu_session_mutator
              @intent_handler = intent_handler
              @rss_reader_screen = rss_reader_screen
              @drag_origin = nil
            end

            # @return [Boolean, Symbol] truthy when the event was consumed
            def handle(event, bounds:)
              return false unless event
              return false unless @rss_reader_screen.reading_pane_active?

              return handle_context_click(event, bounds) if right_click?(event)
              return dispatch_menu_event!(event, bounds) if context_menu_visible?
              return start_drag!(event, bounds) if left_press?(event)
              return extend_drag!(event, bounds) if left_drag?(event)
              return finish_drag(event, bounds) if left_release?(event)

              false
            end

            private

            def right_click?(event) = Shoko::Shared::Terminal::MouseButton.right_click_press?(event)

            def left_release?(event) = Shoko::Shared::Terminal::MouseButton.left_release?(event)

            def left_press?(event)
              button = event[:button].to_i
              !event[:released] && button.nobits?(0b11) && button.nobits?(32) && button.nobits?(64)
            end

            # A drag is the primary button held down while the pointer moves.
            def left_drag?(event)
              button = event[:button].to_i
              !event[:released] && button.allbits?(32) && button.nobits?(0b11)
            end

            def column_of(event)
              terminal_position(event)[:x]
            end

            def row_of(event)
              terminal_position(event)[:y]
            end

            def terminal_position(event)
              Shoko::Shared::Terminal::Coordinates.mouse_to_terminal(event[:x], event[:y])
            end

            def hit_for(event, bounds)
              @rss_reader_screen.reading_hit(column_of(event), row_of(event), bounds)
            end

            # ----- selection -------------------------------------------------

            def start_drag!(event, bounds)
              index = hit_for(event, bounds)
              return clear_selection! unless index

              @drag_origin = { column: column_of(event), row: row_of(event) }
              update_menu(rss_selection: nil, rss_context_menu: nil)
              :handled
            end

            def extend_drag!(event, bounds)
              return false unless @drag_origin

              update_menu(rss_selection: selection_from_origin(event, bounds), rss_context_menu: nil)
              :handled
            end

            def finish_drag(event, bounds)
              return false unless @drag_origin

              update_menu(rss_selection: selection_from_origin(event, bounds))
              true
            ensure
              @drag_origin = nil
            end

            # Stored with its resolved text, so nothing downstream has to know
            # how the article was wrapped to know what was selected.
            def selection_from_origin(event, bounds)
              span = @rss_reader_screen.reading_selection_from_points(
                start_column: @drag_origin[:column], start_row: @drag_origin[:row],
                end_column: column_of(event), end_row: row_of(event), bounds: bounds
              )
              @rss_reader_screen.reading_selection_payload(span, bounds)
            end

            # A click that selects nothing dismisses whatever was selected.
            def clear_selection!
              return false unless current_selection || context_menu_visible?

              update_menu(rss_selection: nil, rss_context_menu: nil)
              :handled
            end

            # ----- the actions menu -----------------------------------------

            # Right-clicking inside the selection opens the menu over it;
            # right-clicking elsewhere selects the word under the pointer first,
            # so the gesture always has something to act on.
            def handle_context_click(event, bounds)
              index = hit_for(event, bounds)
              return clear_selection! unless index

              selection = selection_covering(index) || word_selection_at(index, bounds)
              return clear_selection! unless selection

              update_menu(
                rss_selection: selection,
                rss_context_menu: { anchor_column: column_of(event), anchor_row: row_of(event) }
              )
              :handled
            end

            def dispatch_menu_event!(event, bounds)
              return :handled if left_press?(event)
              return false unless left_release?(event)

              action = @rss_reader_screen.context_menu_hit(column_of(event), row_of(event), bounds)
              action ? dispatch_action(action) : update_menu(rss_context_menu: nil)
              :handled
            end

            # Actions re-enter the use-case layer as intents, the way the book
            # reader's popup does, so the use case owns what each one means.
            def dispatch_action(action)
              @intent_handler.handle_menu_intent(action[:intent], nil)
            end

            def selection_covering(index)
              selection = current_selection
              return nil unless selection

              from, to = Shoko::Shared::IndexRange.ordered(selection)
              index >= from && index < to ? selection : nil
            end

            def word_selection_at(index, bounds)
              @rss_reader_screen.reading_selection_payload(
                @rss_reader_screen.reading_word_at(index, bounds), bounds
              )
            end

            def current_selection
              Shoko::Shared::HashNormalizer.symbolize_keys(@menu_state_reader.rss_selection)
            end

            def context_menu_visible?
              !@menu_state_reader.rss_context_menu.nil?
            end

            def update_menu(payload)
              @menu_session_mutator.update_menu(payload)
              :handled
            end
          end
        end
      end
    end
  end
end
