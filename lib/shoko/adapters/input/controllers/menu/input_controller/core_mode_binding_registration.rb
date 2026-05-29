# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          class InputController
            # Registers the core menu-mode bindings outside the controller body.
            module CoreModeBindingRegistration
              private

              def register_menu_bindings
                bindings = {}
                bind_intent!(bindings,
                             @key_classifier.navigation_keys(:up),
                             :move_menu_selection_up,
                             payload: selection_delta(-1))
                bind_intent!(bindings,
                             @key_classifier.navigation_keys(:down),
                             :move_menu_selection_down,
                             payload: selection_delta(1))
                bind_intent!(bindings, @key_classifier.action_keys(:confirm), :activate_menu_selection)
                bind_intent!(bindings, @key_classifier.action_keys(:quit), :quit_application)
                dispatcher.register_mode(:menu, bindings)
              end

              def register_browse_bindings
                bindings = {}
                bind_intent!(bindings,
                             @key_classifier.navigation_keys(:up),
                             :move_browse_selection_up,
                             payload: selection_delta(-1))
                bind_intent!(bindings,
                             @key_classifier.navigation_keys(:down),
                             :move_browse_selection_down,
                             payload: selection_delta(1))
                bind_intent!(bindings, @key_classifier.action_keys(:confirm), :open_selected_book)
                add_mode_change_bindings(bindings, :switch_to_menu_mode)
                bind_intent!(bindings, ['/'], :switch_to_search_mode)
                dispatcher.register_mode(:browse, bindings)
              end

              def register_search_bindings
                bindings = {}
                bind_intent!(bindings, @key_classifier.action_keys(:backspace), :edit_browse_search,
                             payload: edit_op(:backspace))
                bind_intent!(bindings, @key_classifier.action_keys(:delete), :edit_browse_search,
                             payload: edit_op(:delete))
                bindings[:__default__] = edit_op_text_binding(:edit_browse_search)
                bind_search_navigation(bindings)
                bind_intent!(bindings, @key_classifier.action_keys(:confirm), :open_selected_book)
                bind_intent!(bindings, ['/'], :switch_to_browse_mode)
                bind_intent!(bindings, @key_classifier.action_keys(:cancel), :switch_to_browse_mode)
                dispatcher.register_mode(:search, bindings)
              end

              def register_library_bindings
                bindings = {}
                add_nav_up_down(bindings, :move_library_selection_up, :move_library_selection_down)
                add_confirm_bindings(bindings, :activate_library_selection)
                bind_intent!(bindings, @key_classifier.action_keys(:space), :toggle_library_details)
                add_mode_change_bindings(bindings, :switch_to_menu_mode)
                dispatcher.register_mode(:library, bindings)
              end

              def register_settings_bindings
                bindings = {}
                bind_intent!(bindings,
                             @key_classifier.navigation_keys(:up),
                             :move_settings_selection_up,
                             payload: selection_delta(-1))
                bind_intent!(bindings,
                             @key_classifier.navigation_keys(:down),
                             :move_settings_selection_down,
                             payload: selection_delta(1))
                bind_intent!(bindings, @key_classifier.action_keys(:confirm), :activate_settings_selection)
                bind_intent!(bindings, @key_classifier.action_keys(:space), :activate_settings_selection)
                add_mode_change_bindings(bindings, :switch_to_menu_mode)
                dispatcher.register_mode(:settings, bindings)
              end

              def register_dictionary_bindings
                bindings = {}
                add_nav_up_down(bindings, :move_dictionary_selection_up, :move_dictionary_selection_down)
                add_confirm_bindings(bindings, :activate_dictionary_selection)
                bind_intent!(bindings, @key_classifier.action_keys(:space), :activate_dictionary_selection)
                keys = Array(@key_classifier.action_keys(:quit)) + Array(@key_classifier.action_keys(:cancel))
                bind_intent!(bindings, keys, :close_dictionary_mode)
                bind_intent!(bindings, ['/'], :open_dictionary_mode, payload: mode_change(:dictionary_search))
                bind_intent!(bindings, ['r'], :refresh_dictionary_results)
                dispatcher.register_mode(:dictionary, bindings)
              end

              def register_translator_bindings
                bindings = {}
                bind_intent!(bindings, @key_classifier.action_keys(:backspace), :edit_translator_input,
                             payload: edit_op(:backspace))
                bind_intent!(bindings, @key_classifier.action_keys(:delete), :edit_translator_input,
                             payload: edit_op(:delete))
                bind_intent!(bindings, @key_classifier.action_keys(:confirm), :translator_activate_focus)
                bind_intent!(bindings, ["\t"], :translator_cycle_focus)
                bind_intent!(bindings, ['S'], :translator_swap_languages)
                add_mode_change_bindings(bindings, :close_translator_mode)
                bindings[:__default__] = edit_op_text_binding(:edit_translator_input)
                dispatcher.register_mode(:translator, bindings)
              end
            end
          end
        end
      end
    end
  end
end
