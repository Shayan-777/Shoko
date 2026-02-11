# frozen_string_literal: true

module Shoko
  module Application::Controllers
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

        def add_back_bindings(bindings)
          keys = Array(@key_classifier.action_keys(:quit)) + Array(@key_classifier.action_keys(:cancel))
          keys.each { |k| bindings[k] = :back_to_menu }
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

        def register_menu_bindings
          bindings = {}
          nav_up = @key_classifier.navigation_keys(:up)
          nav_down = @key_classifier.navigation_keys(:down)
          confirm_keys = @key_classifier.action_keys(:confirm)
          quit_keys = @key_classifier.action_keys(:quit)
          nav_up.each { |k| bindings[k] = :menu_up }
          nav_down.each { |k| bindings[k] = :menu_down }
          confirm_keys.each { |k| bindings[k] = :menu_select }
          quit_keys.each { |k| bindings[k] = :menu_quit }
          dispatcher.register_mode(:menu, bindings)
        end

        def register_browse_bindings
          bindings = {}
          add_nav_up_down(bindings, :browse_up, :browse_down)
          add_confirm_bindings(bindings, :browse_select)
          add_back_bindings(bindings)
          bindings['/'] = :start_search
          dispatcher.register_mode(:browse, bindings)
        end

        def register_search_bindings
          bindings = @key_classifier.text_input_commands.text_input_commands(:search_query, nil,
                                                                             cursor_field: :search_cursor)
          arrow_up = ["\e[A", "\eOA"]
          arrow_down = ["\e[B", "\eOB"]
          arrow_up.each { |k| bindings[k] = :browse_up }
          arrow_down.each { |k| bindings[k] = :browse_down }

          confirm_keys = @key_classifier.action_keys(:confirm)
          confirm_keys.each { |k| bindings[k] = :browse_select }
          bindings['/'] = :exit_search
          @key_classifier.action_keys(:cancel).each { |k| bindings[k] = :exit_search }
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
          add_nav_up_down(bindings, :settings_up, :settings_down)
          add_confirm_bindings(bindings, :settings_select)
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
          bindings = @key_classifier.text_input_commands.text_input_commands(:dictionary_query, nil,
                                                                             cursor_field: :dictionary_cursor)
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
          bindings = @key_classifier.text_input_commands.text_input_commands(:download_query, nil,
                                                                             cursor_field: :download_cursor)
          add_confirm_bindings(bindings, :download_submit_search)
          bindings['/'] = :download_exit_search
          @key_classifier.action_keys(:cancel).each { |k| bindings[k] = :download_exit_search }
          dispatcher.register_mode(:download_search, bindings)
        end

        def register_annotations_bindings
          bindings = {}
          add_nav_up_down(bindings, :annotations_up, :annotations_down)
          add_confirm_bindings(bindings, :annotations_select)
          %w[e E].each { |k| bindings[k] = :annotations_edit }
          bindings['d'] = :annotations_delete
          add_back_bindings(bindings)
          dispatcher.register_mode(:annotations, bindings)
        end

        def register_annotation_detail_bindings
          bindings = {}
          %w[o O].each { |k| bindings[k] = :annotation_detail_open }
          %w[e E].each { |k| bindings[k] = :annotation_detail_edit }
          bindings['d'] = :annotation_detail_delete
          @key_classifier.action_keys(:cancel).each { |k| bindings[k] = :annotation_detail_back }
          dispatcher.register_mode(:annotation_detail, bindings)
        end

        def register_annotation_editor_bindings
          bindings = {}
          cancel_cmd = Shoko::Application::Commands::AnnotationEditorCommandFactory.cancel
          @key_classifier.action_keys(:cancel).each { |k| bindings[k] = cancel_cmd }
          @key_classifier.action_keys(:quit).each { |k| bindings[k] = cancel_cmd }

          save_cmd = Shoko::Application::Commands::AnnotationEditorCommandFactory.save
          bindings["\x13"] = save_cmd
          bindings['S'] = save_cmd

          backspace_cmd = Shoko::Application::Commands::AnnotationEditorCommandFactory.backspace
          @key_classifier.action_keys(:backspace).each { |k| bindings[k] = backspace_cmd }

          enter_keys = []
          enter_action = @key_classifier.action_keys(:enter)
          enter_keys += Array(enter_action) if enter_action
          enter_keys += Array(@key_classifier.action_keys(:confirm))
          enter_cmd = Shoko::Application::Commands::AnnotationEditorCommandFactory.enter
          enter_keys.each { |k| bindings[k] = enter_cmd }

          left_cmd = Shoko::Application::Commands::AnnotationEditorCommandFactory.move_left
          right_cmd = Shoko::Application::Commands::AnnotationEditorCommandFactory.move_right
          up_cmd = Shoko::Application::Commands::AnnotationEditorCommandFactory.move_up
          down_cmd = Shoko::Application::Commands::AnnotationEditorCommandFactory.move_down
          arrow_only = ->(keys) { keys.select { |k| k.to_s.start_with?("\e") } }
          arrow_only.call(@key_classifier.navigation_keys(:left)).each { |k| bindings[k] = left_cmd }
          arrow_only.call(@key_classifier.navigation_keys(:right)).each { |k| bindings[k] = right_cmd }
          arrow_only.call(@key_classifier.navigation_keys(:up)).each { |k| bindings[k] = up_cmd }
          arrow_only.call(@key_classifier.navigation_keys(:down)).each { |k| bindings[k] = down_cmd }

          bindings[:__default__] = Shoko::Application::Commands::AnnotationEditorCommandFactory.insert_char
          dispatcher.register_mode(:annotation_editor, bindings)
        end
      end
    end
  end
end
