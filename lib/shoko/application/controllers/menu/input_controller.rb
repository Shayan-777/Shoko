# frozen_string_literal: true

require_relative '../../../adapters/input/dispatcher'
require_relative '../../../adapters/input/command_factory'
require_relative '../../../adapters/input/key_definitions'

module Shoko
  module Application::Controllers
    module Menu
      # Centralises dispatcher setup and key handling for the main menu.
      class InputController
        include Shoko::Adapters::Input::KeyDefinitions::Helpers

        attr_reader :dispatcher

        def initialize(menu)
          @menu = menu
          @state = menu.state
          @dependencies = menu.dependencies
          @dispatcher = Shoko::Adapters::Input::Dispatcher.new(menu)
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

        attr_reader :menu, :state, :dependencies

        def register_bindings
          register_menu_bindings
          register_browse_bindings
          register_search_bindings
          register_library_bindings
          register_settings_bindings
          register_download_bindings
          register_download_search_bindings
          register_annotations_bindings
          register_annotation_detail_bindings
          register_annotation_editor_bindings
        end

        def activate_current_mode
          current_mode = Shoko::Application::Selectors::MenuSelectors.mode(state)
          dispatcher.activate(current_mode)
        end

        def add_back_bindings(bindings)
          keys = Array(Adapters::Input::KeyDefinitions::ACTIONS[:quit]) + Array(Adapters::Input::KeyDefinitions::ACTIONS[:cancel])
          keys.each { |k| bindings[k] = :back_to_menu }
          bindings
        end

        def add_confirm_bindings(bindings, action)
          Adapters::Input::KeyDefinitions::ACTIONS[:confirm].each { |k| bindings[k] = action }
          bindings
        end

        def add_nav_up_down(bindings, up_action, down_action)
          Adapters::Input::KeyDefinitions::NAVIGATION[:up].each { |k| bindings[k] = up_action }
          Adapters::Input::KeyDefinitions::NAVIGATION[:down].each { |k| bindings[k] = down_action }
          bindings
        end

        def register_menu_bindings
          bindings = {}
          nav_up = Adapters::Input::KeyDefinitions::NAVIGATION[:up]
          nav_down = Adapters::Input::KeyDefinitions::NAVIGATION[:down]
          confirm_keys = Adapters::Input::KeyDefinitions::ACTIONS[:confirm]
          quit_keys = Adapters::Input::KeyDefinitions::ACTIONS[:quit]
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
          bindings = Adapters::Input::CommandFactory.text_input_commands(:search_query, nil,
                                                                         cursor_field: :search_cursor)
          arrow_up = ["\e[A", "\eOA"]
          arrow_down = ["\e[B", "\eOB"]
          arrow_up.each { |k| bindings[k] = :browse_up }
          arrow_down.each { |k| bindings[k] = :browse_down }

          confirm_keys = Adapters::Input::KeyDefinitions::ACTIONS[:confirm]
          confirm_keys.each { |k| bindings[k] = :browse_select }
          bindings['/'] = :exit_search
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
          Array(Adapters::Input::KeyDefinitions::ACTIONS[:space]).each { |k| bindings[k] = :settings_select }
          add_back_bindings(bindings)
          dispatcher.register_mode(:settings, bindings)
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
          bindings = Adapters::Input::CommandFactory.text_input_commands(:download_query, nil,
                                                                         cursor_field: :download_cursor)
          add_confirm_bindings(bindings, :download_submit_search)
          bindings['/'] = :download_exit_search
          Adapters::Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = :download_exit_search }
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
          Adapters::Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = :annotation_detail_back }
          dispatcher.register_mode(:annotation_detail, bindings)
        end

        def register_annotation_editor_bindings
          bindings = {}
          cancel_cmd = Shoko::Application::Commands::AnnotationEditorCommandFactory.cancel
          Adapters::Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = cancel_cmd }

          save_cmd = Shoko::Application::Commands::AnnotationEditorCommandFactory.save
          bindings["\x13"] = save_cmd
          bindings['S'] = save_cmd

          backspace_cmd = Shoko::Application::Commands::AnnotationEditorCommandFactory.backspace
          Adapters::Input::KeyDefinitions::ACTIONS[:backspace].each { |k| bindings[k] = backspace_cmd }

          enter_keys = []
          if Adapters::Input::KeyDefinitions::ACTIONS.key?(:enter)
            enter_keys += Array(Adapters::Input::KeyDefinitions::ACTIONS[:enter])
          end
          enter_keys += Array(Adapters::Input::KeyDefinitions::ACTIONS[:confirm])
          enter_cmd = Shoko::Application::Commands::AnnotationEditorCommandFactory.enter
          enter_keys.each { |k| bindings[k] = enter_cmd }

          bindings[:__default__] = Shoko::Application::Commands::AnnotationEditorCommandFactory.insert_char
          dispatcher.register_mode(:annotation_editor, bindings)
        end
      end
    end
  end
end
