# frozen_string_literal: true

require_relative '../../../../shared/text_sanitizer'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Centralises dispatcher setup and key handling for the main menu.
          class InputController
            attr_reader :dispatcher

            def initialize(menu, key_classifier:, input_system_factory:)
              @menu = menu
              @key_classifier = key_classifier
              @dispatcher = input_system_factory.create_menu_dispatcher(menu)
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
              @key_classifier.navigation_keys(:up).each { |k| bindings[k] = :menu_nav_up }
              @key_classifier.navigation_keys(:down).each { |k| bindings[k] = :menu_nav_down }
              @key_classifier.action_keys(:confirm).each { |k| bindings[k] = :menu_select }
              @key_classifier.action_keys(:quit).each { |k| bindings[k] = :menu_quit }
              dispatcher.register_mode(:menu, bindings)
            end

            def register_browse_bindings
              bindings = {}
              @key_classifier.navigation_keys(:up).each { |k| bindings[k] = :browse_up }
              @key_classifier.navigation_keys(:down).each { |k| bindings[k] = :browse_down }
              @key_classifier.action_keys(:confirm).each { |k| bindings[k] = :open_selected_book }
              add_back_bindings(bindings)
              bindings['/'] = :switch_to_search
              dispatcher.register_mode(:browse, bindings)
            end

            def register_search_bindings
              bindings = {}
              @key_classifier.action_keys(:backspace).each { |k| bindings[k] = :search_backspace }
              @key_classifier.action_keys(:delete).each { |k| bindings[k] = :search_delete }
              bindings[:__default__] = :search_insert_char
              @key_classifier.navigation_keys(:up).each { |k| bindings[k] = :browse_up }
              @key_classifier.navigation_keys(:down).each { |k| bindings[k] = :browse_down }
              @key_classifier.action_keys(:confirm).each { |k| bindings[k] = :open_selected_book }
              bindings['/'] = :switch_to_browse
              @key_classifier.action_keys(:cancel).each { |k| bindings[k] = :switch_to_browse }
              dispatcher.register_mode(:search, bindings)
            end

            def register_library_bindings
              bindings = {}
              add_nav_up_down(bindings, :library_up, :library_down)
              add_confirm_bindings(bindings, :library_select)
              add_back_bindings(bindings)
              dispatcher.register_mode(:library, bindings)
            end

            def register_settings_bindings
              bindings = {}
              @key_classifier.navigation_keys(:up).each { |k| bindings[k] = :settings_up }
              @key_classifier.navigation_keys(:down).each { |k| bindings[k] = :settings_down }
              @key_classifier.action_keys(:confirm).each { |k| bindings[k] = :settings_select }
              Array(@key_classifier.action_keys(:space)).each { |k| bindings[k] = :settings_select }
              add_back_bindings(bindings)
              dispatcher.register_mode(:settings, bindings)
            end

            def register_dictionary_bindings
              bindings = {}
              add_nav_up_down(bindings, :dictionary_up, :dictionary_down)
              add_confirm_bindings(bindings, :dictionary_select)
              Array(@key_classifier.action_keys(:space)).each { |k| bindings[k] = :dictionary_select }
              keys = Array(@key_classifier.action_keys(:quit)) + Array(@key_classifier.action_keys(:cancel))
              keys.each { |k| bindings[k] = :dictionary_back }
              bindings['/'] = :dictionary_start_search
              bindings['r'] = :dictionary_refresh
              dispatcher.register_mode(:dictionary, bindings)
            end

            def register_dictionary_search_bindings
              bindings = {}
              @key_classifier.action_keys(:backspace).each { |k| bindings[k] = :dictionary_search_backspace }
              @key_classifier.action_keys(:delete).each { |k| bindings[k] = :dictionary_search_delete }
              bindings[:__default__] = :dictionary_search_insert_char
              add_confirm_bindings(bindings, :dictionary_submit_search)
              bindings['/'] = :dictionary_exit_search
              @key_classifier.action_keys(:cancel).each { |k| bindings[k] = :dictionary_exit_search }
              dispatcher.register_mode(:dictionary_search, bindings)
            end

            def register_download_bindings
              bindings = {}
              add_nav_up_down(bindings, :download_up, :download_down)
              add_confirm_bindings(bindings, :download_confirm)
              add_back_bindings(bindings)
              bindings['/'] = :download_start_search
              %w[n N].each { |k| bindings[k] = :download_next_page }
              %w[p P].each { |k| bindings[k] = :download_prev_page }
              bindings['r'] = :download_refresh
              dispatcher.register_mode(:download, bindings)
            end

            def register_download_search_bindings
              bindings = {}
              @key_classifier.action_keys(:backspace).each { |k| bindings[k] = :download_search_backspace }
              @key_classifier.action_keys(:delete).each { |k| bindings[k] = :download_search_delete }
              bindings[:__default__] = :download_search_insert_char
              add_confirm_bindings(bindings, :download_submit_search)
              bindings['/'] = :download_exit_search
              @key_classifier.action_keys(:cancel).each { |k| bindings[k] = :download_exit_search }
              dispatcher.register_mode(:download_search, bindings)
            end

            def register_annotations_bindings
              bindings = {}
              add_nav_up_down(bindings, :annotations_up, :annotations_down)
              add_confirm_bindings(bindings, :annotations_select)
              %w[e E].each { |k| bindings[k] = :open_selected_annotation_for_edit }
              bindings['d'] = :delete_selected_annotation
              add_back_bindings(bindings)
              dispatcher.register_mode(:annotations, bindings)
            end

            def register_annotation_detail_bindings
              bindings = {}
              %w[o O].each { |k| bindings[k] = :open_selected_annotation }
              %w[e E].each { |k| bindings[k] = :open_selected_annotation_for_edit }
              bindings['d'] = :delete_selected_annotation
              @key_classifier.action_keys(:cancel).each { |k| bindings[k] = :switch_to_annotations_mode }
              dispatcher.register_mode(:annotation_detail, bindings)
            end

            def register_annotation_editor_bindings
              bindings = {}
              @key_classifier.action_keys(:cancel).each { |k| bindings[k] = :annotation_editor_cancel }
              @key_classifier.action_keys(:quit).each { |k| bindings[k] = :annotation_editor_cancel }
              @key_classifier.action_keys(:save).each { |k| bindings[k] = :annotation_editor_save }
              @key_classifier.action_keys(:backspace).each { |k| bindings[k] = :annotation_editor_backspace }

              enter_keys = Array(@key_classifier.action_keys(:confirm))
              enter_keys.each { |k| bindings[k] = :annotation_editor_enter }

              @key_classifier.navigation_keys(:left).each { |k| bindings[k] = :annotation_editor_move_left }
              @key_classifier.navigation_keys(:right).each { |k| bindings[k] = :annotation_editor_move_right }
              @key_classifier.navigation_keys(:up).each { |k| bindings[k] = :annotation_editor_move_up }
              @key_classifier.navigation_keys(:down).each { |k| bindings[k] = :annotation_editor_move_down }

              bindings[:__default__] = :annotation_editor_insert_char
              dispatcher.register_mode(:annotation_editor, bindings)
            end

            def add_back_bindings(bindings)
              keys = Array(@key_classifier.action_keys(:quit)) + Array(@key_classifier.action_keys(:cancel))
              keys.each { |k| bindings[k] = :menu_back_to_root }
              bindings
            end

            def add_confirm_bindings(bindings, action)
              @key_classifier.action_keys(:confirm).each { |k| bindings[k] = action }
              bindings
            end

            def add_nav_up_down(bindings, up_action, down_action)
              @key_classifier.navigation_keys(:up).each { |k| bindings[k] = up_action }
              @key_classifier.navigation_keys(:down).each { |k| bindings[k] = down_action }
              bindings
            end
          end
        end
      end
    end
  end
end
