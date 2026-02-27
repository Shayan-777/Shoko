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
          bindings.merge!(read_mode_local_bindings)

          # When sidebar is visible, redirect up/down/enter to sidebar handlers
          nav_down = Shoko::Shared::KeyDefinitions::NAVIGATION[:down]
          map_keys!(bindings, nav_down, :read_scroll_down_or_sidebar)

          nav_up = Shoko::Shared::KeyDefinitions::NAVIGATION[:up]
          map_keys!(bindings, nav_up, :read_scroll_up_or_sidebar)

          confirm_keys = Shoko::Shared::KeyDefinitions::ACTIONS[:confirm]
          map_keys!(bindings, confirm_keys, :read_confirm_or_sidebar)

          space_keys = Shoko::Shared::KeyDefinitions::ACTIONS[:space]
          map_keys!(bindings, space_keys, :read_space_or_sidebar_toggle)

          @dispatcher.register_mode(:read, bindings)
        end

        def register_popup_menu_bindings(_reader_controller)
          # Popup menu navigation is now handled directly in main_loop via handle_popup_menu_input
          bindings = {}
          map_keys!(bindings, Shoko::Shared::KeyDefinitions::NAVIGATION[:up], :handle_popup_navigation)
          map_keys!(bindings, Shoko::Shared::KeyDefinitions::NAVIGATION[:down], :handle_popup_navigation)
          map_keys!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:confirm], :handle_popup_action_key)
          map_keys!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:cancel], :handle_popup_cancel)
          @dispatcher.register_mode(:popup_menu, bindings)
        end

        def register_help_bindings(_reader_controller)
          bindings = { __default__: :help_exit_to_read }
          @dispatcher.register_mode(:help, bindings)
        end

        def register_library_bindings(_reader_controller)
          # Keys are registered in MainMenu#register_library_bindings; this hook ensures mode exists
          # No-op here as dispatcher registration happens in MainMenu.
        end

        def register_annotation_editor_bindings(_reader_controller)
          bindings = {}

          map_keys!(bindings, ["\e"], :annotation_editor_cancel)

          # Save: Ctrl+S and 'S'
          save_keys = Shoko::Shared::KeyDefinitions::ACTIONS[:save] || []
          map_keys!(bindings, save_keys, :annotation_editor_save)

          # Backspace (both variants)
          map_keys!(bindings, ["\x7F", "\b"], :annotation_editor_backspace)

          # Enter (CR and LF)
          confirm_keys = Shoko::Shared::KeyDefinitions::ACTIONS[:confirm]
          map_keys!(bindings, confirm_keys, :annotation_editor_enter)

          # Cursor movement
          arrow_keys = ->(keys) { keys.select { |k| k.to_s.start_with?("\e") } }
          arrow_keys.call(Shoko::Shared::KeyDefinitions::NAVIGATION[:left]).each do |k|
            bindings[k] = :annotation_editor_move_left
          end
          arrow_keys.call(Shoko::Shared::KeyDefinitions::NAVIGATION[:right]).each do |k|
            bindings[k] = :annotation_editor_move_right
          end
          arrow_keys.call(Shoko::Shared::KeyDefinitions::NAVIGATION[:up]).each do |k|
            bindings[k] = :annotation_editor_move_up
          end
          arrow_keys.call(Shoko::Shared::KeyDefinitions::NAVIGATION[:down]).each do |k|
            bindings[k] = :annotation_editor_move_down
          end

          bindings[:__default__] = :annotation_editor_insert_char_if_printable

          @dispatcher.register_mode(:annotation_editor, bindings)
        end

        def register_dictionary_bindings(_reader_controller)
          bindings = {}

          # Close dictionary with Escape or q
          map_keys!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:cancel], :dictionary_cancel)
          map_keys!(bindings, ['q'], :dictionary_cancel)

          # Navigation - scroll up/down
          map_keys!(bindings, Shoko::Shared::KeyDefinitions::NAVIGATION[:up], :dictionary_scroll_up)
          map_keys!(bindings, Shoko::Shared::KeyDefinitions::NAVIGATION[:down], :dictionary_scroll_down)

          map_keys!(bindings, ['f'], :dictionary_toggle_fuzzy)
          map_keys!(bindings, ["\t"], :dictionary_cycle_result)
          map_keys!(bindings, ['S'], :dictionary_swap_languages)
          map_keys!(bindings, ['L'], :dictionary_cycle_pair)
          map_keys!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:confirm], :dictionary_confirm)
          map_keys!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:backspace], :dictionary_backspace)
          bindings[:__default__] = :dictionary_insert_char_if_printable

          @dispatcher.register_mode(:dictionary, bindings)
        end

        def register_in_book_search_bindings(_reader_controller)
          bindings = {}

          map_keys!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:cancel], :in_book_search_cancel)

          map_keys!(bindings, Shoko::Shared::KeyDefinitions::NAVIGATION[:up], :in_book_search_up)
          map_keys!(bindings, Shoko::Shared::KeyDefinitions::NAVIGATION[:down], :in_book_search_down)

          map_keys!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:confirm], :in_book_search_confirm)
          map_keys!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:backspace], :in_book_search_backspace)

          bindings[:__default__] = :in_book_search_insert_char_if_printable

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
          # Modal modes must be isolated from read-mode fallback bindings.
          @dispatcher.activate(mode)
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

        def read_mode_local_bindings
          reader = Shoko::Shared::KeyDefinitions::READER
          actions = Shoko::Shared::KeyDefinitions::ACTIONS
          bindings = {}

          map_keys!(bindings, reader[:toggle_view], :toggle_view_mode)
          map_keys!(bindings, reader[:toggle_page_mode], :toggle_page_numbering_mode)
          map_keys!(bindings, reader[:increase_spacing], :increase_line_spacing)
          map_keys!(bindings, reader[:decrease_spacing], :decrease_line_spacing)
          map_keys!(bindings, reader[:show_toc], :open_toc)
          map_keys!(bindings, reader[:show_bookmarks], :open_bookmarks)
          map_keys!(bindings, reader[:show_annotations_tab], :open_annotations_tab) if reader.key?(:show_annotations_tab)
          map_keys!(bindings, reader[:show_annotations], :open_annotations) if reader.key?(:show_annotations)
          map_keys!(bindings, reader[:in_book_search], :open_in_book_search) if reader.key?(:in_book_search)
          map_keys!(bindings, reader[:show_help], :show_help)
          map_keys!(bindings, reader[:rebuild_pagination], :rebuild_pagination) if reader.key?(:rebuild_pagination)
          map_keys!(bindings, reader[:invalidate_pagination], :invalidate_pagination_cache) if reader.key?(:invalidate_pagination)

          map_keys!(bindings, reader[:add_bookmark], :add_bookmark)
          map_keys!(bindings, actions[:quit], :quit_to_menu)
          map_keys!(bindings, actions[:force_quit], :quit_application)
          bindings
        end

        def map_keys!(bindings, keys, command_symbol)
          Array(keys).each { |key| bindings[key] = command_symbol }
          bindings
        end

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
