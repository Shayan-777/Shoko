# frozen_string_literal: true

require_relative '../../../../shared/text_sanitizer'
require_relative '../../../../application/use_cases/requests/text_input'
require_relative '../../../../application/use_cases/requests/selection_delta'
require_relative '../../../../application/use_cases/requests/cursor_move'
require_relative '../../../../application/use_cases/requests/mode_change'
require_relative '../../intent_binding'
require_relative 'input_controller/mode_binding_registration'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Centralises dispatcher setup and key handling for the main menu.
          class InputController
            include ModeBindingRegistration

            attr_reader :dispatcher

            def initialize(menu, key_classifier:, input_system_factory:, intent_handler:)
              @menu = menu
              @key_classifier = key_classifier
              @dispatcher = input_system_factory.create_menu_dispatcher(intent_handler: intent_handler)
              register_bindings
              activate_current_mode
            end

            def handle_keys(keys)
              keys.each { |key| dispatcher.handle_key(key) }
            end

            def activate(mode)
              dispatcher.activate(mode)
            end

            private

            attr_reader :menu

            def register_bindings
              register_menu_bindings
              register_browse_bindings
              register_search_bindings
              register_library_bindings
              register_settings_bindings
              register_dictionary_bindings
              register_dictionary_search_bindings
              register_download_bindings
              register_download_search_bindings
              register_download_source_bindings
              register_annotations_bindings
              register_annotation_detail_bindings
              register_annotation_editor_bindings
            end

            def activate_current_mode
              current_mode = menu.menu_state_reader&.mode
              dispatcher.activate(current_mode)
            end

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
              bind_intent!(bindings, @key_classifier.action_keys(:backspace), :browse_backspace)
              bind_intent!(bindings, @key_classifier.action_keys(:delete), :browse_delete)
              bindings[:__default__] = text_input_binding(:browse_insert_text)
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

            def register_dictionary_search_bindings
              bindings = {}
              bind_intent!(bindings, @key_classifier.action_keys(:backspace), :dictionary_query_backspace)
              bind_intent!(bindings, @key_classifier.action_keys(:delete), :dictionary_query_delete)
              bindings[:__default__] = text_input_binding(:dictionary_query_insert_text)
              add_confirm_bindings(bindings, :submit_dictionary_query)
              bind_intent!(bindings, ['/'], :close_dictionary_mode, payload: mode_change(:dictionary))
              bind_intent!(bindings,
                           @key_classifier.action_keys(:cancel),
                           :close_dictionary_mode,
                           payload: mode_change(:dictionary))
              dispatcher.register_mode(:dictionary_search, bindings)
            end

            def add_confirm_bindings(bindings, action)
              bind_intent!(bindings, @key_classifier.action_keys(:confirm), action)
              bindings
            end

            def add_nav_up_down(bindings, up_action, down_action)
              bind_intent!(bindings, @key_classifier.navigation_keys(:up), up_action, payload: selection_delta(-1))
              bind_intent!(bindings, @key_classifier.navigation_keys(:down), down_action, payload: selection_delta(1))
              bindings
            end

            def bind_search_navigation(bindings)
              add_nav_up_down(bindings, :move_browse_selection_up, :move_browse_selection_down)
            end

            def add_mode_change_bindings(bindings, action)
              keys = Array(@key_classifier.action_keys(:quit)) + Array(@key_classifier.action_keys(:cancel))
              bind_intent!(bindings, keys, action)
              bindings
            end

            def bind_intent!(bindings, keys, intent, payload: nil)
              binding = Adapters::Input::IntentBinding.new(intent, payload: payload)
              Array(keys).each { |key| bindings[key] = binding }
              bindings
            end

            def text_input_binding(intent)
              Adapters::Input::IntentBinding.new(intent) do |key|
                char = key.to_s
                if Shoko::Shared::TextSanitizer.printable_char?(char)
                  Shoko::Application::UseCases::Requests::TextInput.new(text: char)
                else
                  Adapters::Input::IntentBinding.skip
                end
              end
            end

            def selection_delta(delta)
              Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: delta)
            end

            def cursor_move(direction)
              Shoko::Application::UseCases::Requests::CursorMove.new(direction: direction)
            end

            def mode_change(mode)
              Shoko::Application::UseCases::Requests::ModeChange.new(mode: mode)
            end
          end
        end
      end
    end
  end
end
