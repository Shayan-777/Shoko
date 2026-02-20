# frozen_string_literal: true

require_relative '../../shared/key_definitions'

module Shoko
  module Adapters
    module Input
      # Handles all input processing: key handling, popup management, mode switching
      class ReaderInputController
        def initialize(reader_state_reader:, state_writer:, command_bus:, ui_controller: nil)
          @ui_controller = ui_controller
          @dispatcher = nil
          @modal_mode_stack = []
          @reader_state_reader = reader_state_reader
          @state_writer = state_writer
          @command_bus = command_bus
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
          popup_menu = reader_state_reader&.popup_menu
          return unless popup_menu

          keys.each do |key|
            res = popup_menu.handle_key(key) || { type: :noop }
            process_popup_result(res)
          end
        end

        def handle_annotations_overlay_input(keys)
          ctrl = ui_controller
          return unless ctrl

          keys.each do |key|
            result = annotation_overlay_result_for(ctrl, key)
            next unless result
          end
        end

        private

        def annotation_overlay_result_for(ctrl, key)
          if Shoko::Shared::KeyDefinitions::Helpers.up_key?(key)
            ctrl.annotations_up
          elsif Shoko::Shared::KeyDefinitions::Helpers.down_key?(key)
            ctrl.annotations_down
          elsif Shoko::Shared::KeyDefinitions::Helpers.confirm_key?(key)
            ctrl.annotations_open
          elsif %w[e E].include?(key)
            ctrl.annotations_edit
          elsif key == 'd'
            ctrl.annotations_delete
          elsif Shoko::Shared::KeyDefinitions::Helpers.cancel_key?(key)
            ctrl.annotations_cancel
          end
        end

        def with_popup_menu
          popup_menu = reader_state_reader&.popup_menu
          return :pass unless popup_menu

          yield popup_menu
        end

        def ui_controller
          @ui_controller
        end

        def process_popup_result(result, _controller = ui_controller)
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

          # Register non-read modes expected by reader state transitions.
          register_help_bindings(reader_controller)
          register_annotation_editor_bindings(reader_controller)
          register_library_bindings(reader_controller)
          register_dictionary_bindings(reader_controller)
          register_in_book_search_bindings(reader_controller)
        end

        def register_read_bindings(_reader_controller)
          bindings = Adapters::Input::CommandFactory.reader_navigation_commands
          bindings.merge!(Adapters::Input::CommandFactory.reader_control_commands)

          # When sidebar is visible, redirect up/down/enter to sidebar handlers
          nav_down = Shoko::Shared::KeyDefinitions::NAVIGATION[:down]
          nav_down.each do |key|
            bindings[key] = :conditional_down
          end

          nav_up = Shoko::Shared::KeyDefinitions::NAVIGATION[:up]
          nav_up.each do |key|
            bindings[key] = :conditional_up
          end

          confirm_keys = Shoko::Shared::KeyDefinitions::ACTIONS[:confirm]
          confirm_keys.each do |key|
            bindings[key] = :conditional_select
          end

          space_keys = Shoko::Shared::KeyDefinitions::ACTIONS[:space]
          space_keys.each do |key|
            bindings[key] = :conditional_space
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

        def register_help_bindings(_reader_controller)
          bindings = { __default__: :exit_help }
          @dispatcher.register_mode(:help, bindings)
        end

        def register_library_bindings(_reader_controller)
          # Keys are registered in MainMenu#register_library_bindings; this hook ensures mode exists
          # No-op here as dispatcher registration happens in MainMenu.
        end

        def register_annotation_editor_bindings(_reader_controller)
          bindings = {}

          # Use command symbols that will be resolved via command_bus
          cancel_cmd = :annotation_editor_cancel
          save_cmd   = :annotation_editor_save
          back_cmd   = :annotation_editor_backspace
          enter_cmd  = :annotation_editor_enter
          left_cmd   = :annotation_editor_move_left
          right_cmd  = :annotation_editor_move_right
          up_cmd     = :annotation_editor_move_up
          down_cmd   = :annotation_editor_move_down

          # Cancel editor
          bindings["\e"] = cancel_cmd

          # Save: Ctrl+S and 'S'
          save_keys = Shoko::Shared::KeyDefinitions::ACTIONS[:save] || []
          save_keys.each { |k| bindings[k] = save_cmd }

          # Backspace (both variants)
          bindings["\x7F"] = back_cmd
          bindings["\b"]   = back_cmd

          # Enter (CR and LF)
          confirm_keys = Shoko::Shared::KeyDefinitions::ACTIONS[:confirm]
          confirm_keys.each { |k| bindings[k] = enter_cmd }

          # Cursor movement
          arrow_keys = ->(keys) { keys.select { |k| k.to_s.start_with?("\e") } }
          arrow_keys.call(Shoko::Shared::KeyDefinitions::NAVIGATION[:left]).each { |k| bindings[k] = left_cmd }
          arrow_keys.call(Shoko::Shared::KeyDefinitions::NAVIGATION[:right]).each { |k| bindings[k] = right_cmd }
          arrow_keys.call(Shoko::Shared::KeyDefinitions::NAVIGATION[:up]).each { |k| bindings[k] = up_cmd }
          arrow_keys.call(Shoko::Shared::KeyDefinitions::NAVIGATION[:down]).each { |k| bindings[k] = down_cmd }

          # Default: insert printable characters via lambda that uses command_bus
          bindings[:__default__] = lambda { |ctx, key|
            char = key.to_s
            cmd = command_bus&.build_command(:annotation_editor_insert_char, char: char)
            cmd&.execute(ctx, key: key) || :pass
          }

          @dispatcher.register_mode(:annotation_editor, bindings)
        end

        def register_dictionary_bindings(_reader_controller)
          bindings = {}

          # Close dictionary with Escape or q
          Shoko::Shared::KeyDefinitions::ACTIONS[:cancel].each do |key|
            bindings[key] = :dictionary_cancel
          end
          bindings['q'] = :dictionary_cancel

          # Navigation - scroll up/down
          Shoko::Shared::KeyDefinitions::NAVIGATION[:up].each do |key|
            bindings[key] = :dictionary_scroll_up
          end
          Shoko::Shared::KeyDefinitions::NAVIGATION[:down].each do |key|
            bindings[key] = :dictionary_scroll_down
          end

          bindings['f'] = :dictionary_toggle_fuzzy
          bindings["\t"] = :dictionary_cycle_result
          bindings['S'] = :dictionary_swap_languages
          bindings['L'] = :dictionary_cycle_pair
          Shoko::Shared::KeyDefinitions::ACTIONS[:confirm].each do |key|
            bindings[key] = :dictionary_confirm
          end
          Shoko::Shared::KeyDefinitions::ACTIONS[:backspace].each do |key|
            bindings[key] = :dictionary_backspace
          end
          bindings[:__default__] = :dictionary_insert_char

          @dispatcher.register_mode(:dictionary, bindings)
        end

        def register_in_book_search_bindings(_reader_controller)
          bindings = {}

          Shoko::Shared::KeyDefinitions::ACTIONS[:cancel].each do |key|
            bindings[key] = :in_book_search_cancel
          end

          Shoko::Shared::KeyDefinitions::NAVIGATION[:up].each do |key|
            bindings[key] = :in_book_search_up
          end
          Shoko::Shared::KeyDefinitions::NAVIGATION[:down].each do |key|
            bindings[key] = :in_book_search_down
          end

          Shoko::Shared::KeyDefinitions::ACTIONS[:confirm].each do |key|
            bindings[key] = :in_book_search_confirm
          end
          Shoko::Shared::KeyDefinitions::ACTIONS[:backspace].each do |key|
            bindings[key] = :in_book_search_backspace
          end

          bindings[:__default__] = :in_book_search_insert_char

          @dispatcher.register_mode(:in_book_search, bindings)
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
          when :in_book_search
            @dispatcher.activate(:in_book_search)
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
            mode = reader_state_reader&.mode || :read
            activate_for_mode(mode)
          end
        end

        private

        def reader_state_reader
          @reader_state_reader
        end

        def state_writer
          @state_writer
        end

        def command_bus
          @command_bus
        end

        # Removed reader annotations list bindings; annotations are managed via the sidebar
      end
    end
  end
end
