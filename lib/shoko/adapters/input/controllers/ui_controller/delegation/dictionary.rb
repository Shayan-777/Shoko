# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module UiControllerDelegation
          module Dictionary
            def handle_lookup_action(action_data)
              @dictionary_controller.handle_lookup_action(action_data)
            end

            def show_dictionary_panel(result, announce: true)
              @dictionary_controller.show_dictionary_panel(result, announce: announce)
            end

            def show_dictionary_popup(result, announce: true)
              @dictionary_controller.show_dictionary_popup(result, announce: announce)
            end

            def close_dictionary(_key = nil)
              @dictionary_controller.close_dictionary
            end

            def dictionary_insert_char(char)
              @dictionary_controller.dictionary_insert_char(char)
            end

            def dictionary_backspace(key = nil)
              @dictionary_controller.dictionary_backspace(key)
            end

            def dictionary_confirm(key = nil)
              @dictionary_controller.dictionary_confirm(key)
            end

            def dictionary_cancel(key = nil)
              @dictionary_controller.dictionary_cancel(key)
            end

            def dictionary_tab(key = nil)
              @dictionary_controller.dictionary_tab(key)
            end

            def dictionary_swap_languages(key = nil)
              @dictionary_controller.dictionary_swap_languages(key)
            end

            def refresh_dictionary_display_mode(terminal_width:, terminal_height:)
              @dictionary_controller.refresh_dictionary_display_mode(
                terminal_width: terminal_width,
                terminal_height: terminal_height
              )
            end

            def dictionary_scroll_up(key = nil)
              @dictionary_controller.dictionary_scroll_up(key)
            end

            def dictionary_scroll_down(key = nil)
              @dictionary_controller.dictionary_scroll_down(key)
            end

            def dictionary_toggle_fuzzy(key = nil)
              @dictionary_controller.dictionary_toggle_fuzzy(key)
            end

            def dictionary_cycle_result(key = nil)
              @dictionary_controller.dictionary_cycle_result(key)
            end

            def dictionary_cycle_pair(key = nil)
              @dictionary_controller.dictionary_cycle_pair(key)
            end

            def active_dictionary_component
              @dictionary_controller.active_dictionary_component
            end

            def dictionary_visible?
              @dictionary_controller.dictionary_visible?
            end

            def determine_dictionary_display_mode(terminal_width, terminal_height)
              @dictionary_controller.determine_dictionary_display_mode(terminal_width, terminal_height)
            end
          end
        end
      end
    end
  end
end
