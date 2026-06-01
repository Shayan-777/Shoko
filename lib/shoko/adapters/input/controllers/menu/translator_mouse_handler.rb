# frozen_string_literal: true

require_relative '../../../../shared/hash_normalizer'
require_relative 'translator_mouse_handler/interaction_flow'
require_relative 'translator_mouse_handler/clipboard_actions'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Handles translator-screen mouse selection and clipboard context-menu interactions.
          class TranslatorMouseHandler
            include InteractionFlow
            include ClipboardActions

            def initialize(
              menu_state_reader:,
              menu_session_mutator:,
              input_controller:,
              translator_screen:,
              clipboard_service: nil,
              notification_service: nil
            )
              @menu_state_reader = menu_state_reader
              @menu_session_mutator = menu_session_mutator
              @input_controller = input_controller
              @translator_screen = translator_screen
              @clipboard_service = clipboard_service
              @notification_service = notification_service
              @drag_origin = nil
            end

            def handle(event, bounds:)
              return false unless event
              return false unless @menu_state_reader.mode.to_sym == :translator

              return handle_context_click(event, bounds) if right_click_press?(event)
              return dispatch_popup_event!(event, bounds) if context_menu_visible?
              return start_drag_interaction!(event, bounds) if left_button_press?(event)
              return update_drag_selection!(event, bounds) if left_drag?(event)
              return finish_drag_interaction(event, bounds) if left_button_release?(event)

              false
            end

            private

            def selection_contains_hit?(selection, hit)
              @translator_screen.selection_contains_hit?(selection, hit)
            end

            def source_selection?(selection)
              selection && selection[:pane].to_sym == :source
            end

            def selection_bounds(selection)
              start_index = selection[:start_index].to_i
              end_index = selection[:end_index].to_i
              start_index <= end_index ? [start_index, end_index] : [end_index, start_index]
            end

            def current_source_cursor
              @menu_state_reader.translator_input_cursor.to_i.clamp(0, translator_input_length)
            end

            def translator_input_length
              @menu_state_reader.translator_input_text.to_s.length
            end

            def context_menu_visible?
              !current_context_menu.nil?
            end

            def current_selection
              normalize_hash(@menu_state_reader.translator_selection)
            end

            def current_context_menu
              normalize_hash(@menu_state_reader.translator_context_menu)
            end

            def normalize_hash(value)
              return nil unless value.is_a?(Hash)

              Shoko::Shared::HashNormalizer.symbolize_keys(value)
            end

            def body_hit_for(event, bounds)
              @translator_screen.body_hit(terminal_column(event), terminal_row(event), bounds)
            end

            def terminal_column(event)
              event[:x].to_i + 1
            end

            def terminal_row(event)
              event[:y].to_i + 1
            end

            def clear_context_menu!
              update_menu(translator_context_menu: nil)
              :cleared
            end

            def update_menu(payload)
              @menu_session_mutator.update_menu(payload)
            end

            def notify(message)
              @notification_service&.set_message(message.to_s.strip)
            end

            def left_button_press?(event)
              !event[:released] && event[:button].to_i.zero?
            end

            def left_button_release?(event)
              event[:released] && event[:button].to_i.zero?
            end

            def left_drag?(event)
              button = event[:button].to_i
              !event[:released] && button.anybits?(32) && button.nobits?(0b11)
            end

            def right_click_press?(event)
              button = event[:button].to_i
              !event[:released] && (button & 0b11) == 2 && button.nobits?(32)
            end
          end
        end
      end
    end
  end
end
