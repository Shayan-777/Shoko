# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      # Handles all input processing: key handling, popup management, mode switching
      class InputController
        def initialize(state, dependencies, ui_controller: nil)
          @state = state
          @dependencies = dependencies
          @ui_controller = ui_controller
          @dispatcher = nil
          @modal_mode_stack = []
        end

        def setup_input_dispatcher(reader_controller)
          @dispatcher = Adapters::Input::Dispatcher.new(reader_controller)
          setup_consolidated_reader_bindings(reader_controller)
          @dispatcher.activate_stack([:read])
        end

        def handle_key(key)
          @dispatcher&.handle_key(key)
        end

        # Enhanced popup navigation handlers for direct key routing
        def handle_popup_navigation(key)
          with_popup_menu do |menu|
            res = menu.handle_key(key)
            next :pass unless res

            :handled
          end
        end

        def handle_popup_action_key(key)
          with_popup_menu do |menu|
            res = menu.handle_key(key) || { type: :noop }
            process_popup_result(res)
          end
        end

        def handle_popup_cancel(key)
          with_popup_menu do |menu|
            res = menu.handle_key(key) || { type: :noop }
            process_popup_result(res)
          end
        end

        def handle_popup_menu_input(keys)
          popup_menu = Shoko::Application::Selectors::ReaderSelectors.popup_menu(@state)
          return unless popup_menu

          keys.each do |key|
            res = popup_menu.handle_key(key) || { type: :noop }
            process_popup_result(res)
          end
        end

        def handle_annotations_overlay_input(keys)
          overlay = Shoko::Application::Selectors::ReaderSelectors.annotations_overlay(@state)
          return unless overlay

          ctrl = ui_controller
          keys.each do |key|
            result = overlay.handle_key(key)
            next unless result

            case result[:type]
            when :selection_change
              index = result[:index]
              @state.dispatch(Shoko::Application::Actions::UpdateSidebarAction.new(
                                annotations_selected: index,
                                sidebar_annotations_selected: index
                              ))
            when :open
              ctrl.open_annotation_from_overlay(result[:annotation]) if ctrl.respond_to?(:open_annotation_from_overlay)
            when :edit
              ctrl.edit_annotation_from_overlay(result[:annotation]) if ctrl.respond_to?(:edit_annotation_from_overlay)
            when :delete
              ctrl.delete_annotation_from_overlay(result[:annotation]) if ctrl.respond_to?(:delete_annotation_from_overlay)
            when :close
              ctrl.close_annotations_overlay if ctrl.respond_to?(:close_annotations_overlay)
            end
          end
        end

        def handle_dictionary_input(keys)
          ctrl = ui_controller
          return unless ctrl

          keys.each do |key|
            ctrl.handle_dictionary_key(key)
          end
        end

        private

        def with_popup_menu
          popup_menu = Shoko::Application::Selectors::ReaderSelectors.popup_menu(@state)
          return :pass unless popup_menu

          yield popup_menu
        end

        def ui_controller
          @ui_controller ||= @dependencies.resolve(:ui_controller)
        end

        def process_popup_result(result, controller = ui_controller)
          case result[:type]
          when :selection_change
            # Selection change handled by popup itself
            :handled
          when :action
            ui_controller.handle_popup_action(result)
            :handled
          when :cancel
            ui_controller.cleanup_popup_state
            ui_controller.switch_mode(:read)
            :handled
          else
            :pass
          end
        end

        def setup_consolidated_reader_bindings(reader_controller)
          # Register reader mode bindings using Adapters::Input::CommandFactory patterns
          register_read_bindings(reader_controller)
          register_popup_menu_bindings(reader_controller)

          # Keep legacy bindings for modes not yet converted
          register_help_bindings_new(reader_controller)
          register_annotation_editor_bindings_new(reader_controller)
          register_library_bindings_new(reader_controller)
          register_dictionary_bindings_new(reader_controller)
        end

        def register_read_bindings(_reader_controller)
          bindings = Adapters::Input::CommandFactory.reader_navigation_commands
          bindings.merge!(Adapters::Input::CommandFactory.reader_control_commands)

          # When sidebar is visible, redirect up/down/enter to sidebar handlers
          nav_down = Adapters::Input::KeyDefinitions::NAVIGATION[:down]
          nav_down.each do |key|
            bindings[key] = :conditional_down
          end

          nav_up = Adapters::Input::KeyDefinitions::NAVIGATION[:up]
          nav_up.each do |key|
            bindings[key] = :conditional_up
          end

          confirm_keys = Adapters::Input::KeyDefinitions::ACTIONS[:confirm]
          confirm_keys.each do |key|
            bindings[key] = :conditional_select
          end

          # Ensure TOC toggle is bound explicitly and marked handled
          %w[t T].each do |key|
            bindings[key] = :open_toc
          end

          @dispatcher.register_mode(:read, bindings)
        end

        def register_popup_menu_bindings(_reader_controller)
          # Popup menu navigation is now handled directly in main_loop via handle_popup_menu_input
          bindings = {}
          bindings.merge!(Adapters::Input::CommandFactory.menu_selection_commands)
          bindings.merge!(Adapters::Input::CommandFactory.exit_commands(:exit_popup_menu))
          @dispatcher.register_mode(:popup_menu, bindings)
        end

        def register_help_bindings_new(_reader_controller)
          bindings = { __default__: :exit_help }
          @dispatcher.register_mode(:help, bindings)
        end

        def register_library_bindings_new(_reader_controller)
          # Keys are registered in MainMenu#register_library_bindings; this hook ensures mode exists
          # No-op here as dispatcher registration happens in MainMenu.
        end

        def register_annotation_editor_bindings_new(_reader_controller)
          bindings = {}

          cancel_cmd = Shoko::Application::Commands::AnnotationEditorCommandFactory.cancel
          save_cmd   = Shoko::Application::Commands::AnnotationEditorCommandFactory.save
          back_cmd   = Shoko::Application::Commands::AnnotationEditorCommandFactory.backspace
          enter_cmd  = Shoko::Application::Commands::AnnotationEditorCommandFactory.enter
          insert_cmd = Shoko::Application::Commands::AnnotationEditorCommandFactory.insert_char

          # Cancel editor
          bindings["\e"] = cancel_cmd

          # Save: Ctrl+S and 'S'
          bindings["\x13"] = save_cmd
          bindings['S'] = save_cmd

          # Backspace (both variants)
          bindings["\x7F"] = back_cmd
          bindings["\b"]   = back_cmd

          # Enter (CR and LF)
          confirm_keys = Adapters::Input::KeyDefinitions::ACTIONS[:confirm]
          confirm_keys.each { |k| bindings[k] = enter_cmd }

          # Default: insert printable characters
          bindings[:__default__] = insert_cmd

          @dispatcher.register_mode(:annotation_editor, bindings)
        end

        def register_dictionary_bindings_new(_reader_controller)
          bindings = {}

          # Close dictionary with Escape or q
          Adapters::Input::KeyDefinitions::ACTIONS[:cancel].each do |key|
            bindings[key] = :close_dictionary
          end
          bindings['q'] = :close_dictionary

          # Navigation - scroll up/down
          Adapters::Input::KeyDefinitions::NAVIGATION[:up].each do |key|
            bindings[key] = :dictionary_scroll_up
          end
          Adapters::Input::KeyDefinitions::NAVIGATION[:down].each do |key|
            bindings[key] = :dictionary_scroll_down
          end

          bindings['f'] = :dictionary_toggle_fuzzy
          bindings["\t"] = :dictionary_cycle_result
          bindings['L'] = :dictionary_cycle_pair

          @dispatcher.register_mode(:dictionary, bindings)
        end

        public

        # Switch active bindings according to mode
        def activate_for_mode(mode)
          return unless @dispatcher

          @modal_mode_stack.clear
          case mode
          when :annotation_editor
            @dispatcher.activate(:annotation_editor)
          when :help
            @dispatcher.activate(:help)
          when :dictionary
            @dispatcher.activate(:dictionary)
          else
            @dispatcher.activate_stack([:read])
          end
        end

        def enter_modal_mode(mode)
          return unless @dispatcher

          current_stack = @dispatcher.mode_stack
          return if current_stack.last == mode

          @modal_mode_stack << current_stack
          new_stack = current_stack.empty? ? [mode] : current_stack + [mode]
          @dispatcher.activate_stack(new_stack)
        end

        def exit_modal_mode(_mode)
          return unless @dispatcher

          previous_stack = @modal_mode_stack.pop
          if previous_stack&.any?
            @dispatcher.activate_stack(previous_stack)
          else
            activate_for_mode(@state.get(%i[reader mode]) || :read)
          end
        end

        # Removed reader annotations list bindings; annotations are managed via the sidebar
      end
    end
  end
end
