# frozen_string_literal: true

require_relative '../../shared/key_definitions'
require_relative '../../shared/text_sanitizer'

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
          nav_down.each do |key|
            bindings[key] = conditional_binding(primary_command: :scroll_down, sidebar_action: :sidebar_down)
          end

          nav_up = Shoko::Shared::KeyDefinitions::NAVIGATION[:up]
          nav_up.each do |key|
            bindings[key] = conditional_binding(primary_command: :scroll_up, sidebar_action: :sidebar_up)
          end

          confirm_keys = Shoko::Shared::KeyDefinitions::ACTIONS[:confirm]
          confirm_keys.each do |key|
            bindings[key] = conditional_binding(primary_command: :next_page, sidebar_action: :sidebar_select)
          end

          space_keys = Shoko::Shared::KeyDefinitions::ACTIONS[:space]
          space_keys.each do |key|
            bindings[key] = conditional_binding(
              primary_command: :next_page,
              sidebar_action: :sidebar_toggle_toc,
              toc_only: true
            )
          end

          @dispatcher.register_mode(:read, bindings)
        end

        def register_popup_menu_bindings(_reader_controller)
          # Popup menu navigation is now handled directly in main_loop via handle_popup_menu_input
          bindings = {}
          bindings.merge!(Adapters::Input::CommandFactory.menu_selection_commands)
          Shoko::Shared::KeyDefinitions::ACTIONS[:cancel].each do |key|
            bindings[key] = lambda do |ctx, _|
              next :pass unless ctx.respond_to?(:cleanup_popup_state) && ctx.respond_to?(:switch_mode)

              ctx.cleanup_popup_state
              ctx.switch_mode(:read)
              :handled
            end
          end
          @dispatcher.register_mode(:popup_menu, bindings)
        end

        def register_help_bindings(_reader_controller)
          bindings = {
            __default__: lambda do |ctx, _|
              next :pass unless ctx.respond_to?(:switch_mode)

              ctx.switch_mode(:read)
              :handled
            end
          }
          @dispatcher.register_mode(:help, bindings)
        end

        def register_library_bindings(_reader_controller)
          # Keys are registered in MainMenu#register_library_bindings; this hook ensures mode exists
          # No-op here as dispatcher registration happens in MainMenu.
        end

        def register_annotation_editor_bindings(_reader_controller)
          bindings = {}

          bindings["\e"] = annotation_editor_action(:cancel_annotation)

          # Save: Ctrl+S and 'S'
          save_keys = Shoko::Shared::KeyDefinitions::ACTIONS[:save] || []
          save_keys.each { |k| bindings[k] = annotation_editor_action(:save_annotation) }

          # Backspace (both variants)
          bindings["\x7F"] = annotation_editor_action(:handle_backspace)
          bindings["\b"]   = annotation_editor_action(:handle_backspace)

          # Enter (CR and LF)
          confirm_keys = Shoko::Shared::KeyDefinitions::ACTIONS[:confirm]
          confirm_keys.each { |k| bindings[k] = annotation_editor_action(:handle_enter) }

          # Cursor movement
          arrow_keys = ->(keys) { keys.select { |k| k.to_s.start_with?("\e") } }
          arrow_keys.call(Shoko::Shared::KeyDefinitions::NAVIGATION[:left]).each do |k|
            bindings[k] = annotation_editor_action(:handle_move_left)
          end
          arrow_keys.call(Shoko::Shared::KeyDefinitions::NAVIGATION[:right]).each do |k|
            bindings[k] = annotation_editor_action(:handle_move_right)
          end
          arrow_keys.call(Shoko::Shared::KeyDefinitions::NAVIGATION[:up]).each do |k|
            bindings[k] = annotation_editor_action(:handle_move_up)
          end
          arrow_keys.call(Shoko::Shared::KeyDefinitions::NAVIGATION[:down]).each do |k|
            bindings[k] = annotation_editor_action(:handle_move_down)
          end

          bindings[:__default__] = annotation_editor_action(:handle_character, character_arg: true)

          @dispatcher.register_mode(:annotation_editor, bindings)
        end

        def register_dictionary_bindings(_reader_controller)
          bindings = {}

          # Close dictionary with Escape or q
          Shoko::Shared::KeyDefinitions::ACTIONS[:cancel].each do |key|
            bindings[key] = local_action(:dictionary_cancel)
          end
          bindings['q'] = local_action(:dictionary_cancel)

          # Navigation - scroll up/down
          Shoko::Shared::KeyDefinitions::NAVIGATION[:up].each do |key|
            bindings[key] = local_action(:dictionary_scroll_up)
          end
          Shoko::Shared::KeyDefinitions::NAVIGATION[:down].each do |key|
            bindings[key] = local_action(:dictionary_scroll_down)
          end

          bindings['f'] = local_action(:dictionary_toggle_fuzzy)
          bindings["\t"] = local_action(:dictionary_cycle_result)
          bindings['S'] = local_action(:dictionary_swap_languages)
          bindings['L'] = local_action(:dictionary_cycle_pair)
          Shoko::Shared::KeyDefinitions::ACTIONS[:confirm].each do |key|
            bindings[key] = local_action(:dictionary_confirm)
          end
          Shoko::Shared::KeyDefinitions::ACTIONS[:backspace].each do |key|
            bindings[key] = local_action(:dictionary_backspace)
          end
          bindings[:__default__] = character_action(:dictionary_insert_char)

          @dispatcher.register_mode(:dictionary, bindings)
        end

        def register_in_book_search_bindings(_reader_controller)
          bindings = {}

          Shoko::Shared::KeyDefinitions::ACTIONS[:cancel].each do |key|
            bindings[key] = local_action(:in_book_search_cancel)
          end

          Shoko::Shared::KeyDefinitions::NAVIGATION[:up].each do |key|
            bindings[key] = local_action(:in_book_search_up)
          end
          Shoko::Shared::KeyDefinitions::NAVIGATION[:down].each do |key|
            bindings[key] = local_action(:in_book_search_down)
          end

          Shoko::Shared::KeyDefinitions::ACTIONS[:confirm].each do |key|
            bindings[key] = local_action(:in_book_search_confirm)
          end
          Shoko::Shared::KeyDefinitions::ACTIONS[:backspace].each do |key|
            bindings[key] = local_action(:in_book_search_backspace)
          end

          bindings[:__default__] = character_action(:in_book_search_insert_char)

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

        def read_mode_local_bindings
          reader = Shoko::Shared::KeyDefinitions::READER
          actions = Shoko::Shared::KeyDefinitions::ACTIONS
          bindings = {}

          map_local!(bindings, reader[:toggle_view], :toggle_view_mode)
          map_local!(bindings, reader[:toggle_page_mode], :toggle_page_numbering_mode)
          map_local!(bindings, reader[:increase_spacing], :increase_line_spacing)
          map_local!(bindings, reader[:decrease_spacing], :decrease_line_spacing)
          map_local!(bindings, reader[:show_toc], :open_toc)
          map_local!(bindings, reader[:show_bookmarks], :open_bookmarks)
          map_local!(bindings, reader[:show_annotations_tab], :open_annotations_tab) if reader.key?(:show_annotations_tab)
          map_local!(bindings, reader[:show_annotations], :open_annotations) if reader.key?(:show_annotations)
          map_local!(bindings, reader[:in_book_search], :open_in_book_search) if reader.key?(:in_book_search)
          map_local!(bindings, reader[:show_help], :show_help)
          map_local!(bindings, reader[:rebuild_pagination], :rebuild_pagination) if reader.key?(:rebuild_pagination)
          map_local!(bindings, reader[:invalidate_pagination], :invalidate_pagination_cache) if reader.key?(:invalidate_pagination)

          map_semantic!(bindings, reader[:add_bookmark], :add_bookmark)
          map_local!(bindings, actions[:quit], :quit_to_menu)
          map_local!(bindings, actions[:force_quit], :quit_application)
          bindings
        end

        def map_local!(bindings, keys, action)
          Array(keys).each { |key| bindings[key] = local_action(action) }
        end

        def map_semantic!(bindings, keys, command_symbol)
          Array(keys).each { |key| bindings[key] = command_symbol }
        end

        def local_action(action)
          lambda do |ctx, key|
            dispatch_local_action(ctx, action, key)
          end
        end

        def character_action(action)
          lambda do |ctx, key|
            char = key.to_s
            next :pass unless Shoko::Shared::TextSanitizer.printable_char?(char)

            dispatch_local_action(ctx, action, char)
          end
        end

        def annotation_editor_action(action, character_arg: false)
          lambda do |ctx, key|
            editor = annotation_editor_component(ctx)
            next :pass unless editor&.respond_to?(action)

            if character_arg
              char = key.to_s
              next :pass unless Shoko::Shared::TextSanitizer.printable_char?(char)

              editor.public_send(action, char)
            else
              editor.public_send(action)
            end
            :handled
          rescue StandardError
            :pass
          end
        end

        def annotation_editor_component(ctx)
          return nil unless ctx.respond_to?(:current_editor_component)

          ctx.current_editor_component
        rescue StandardError
          nil
        end

        def conditional_binding(primary_command:, sidebar_action:, toc_only: false)
          lambda do |ctx, key|
            if sidebar_visible?(ctx) && (!toc_only || sidebar_toc_tab?(ctx))
              dispatch_local_action(ctx, sidebar_action, key)
            else
              execute_semantic_command(ctx, primary_command, key)
            end
          end
        end

        def sidebar_visible?(ctx)
          reader = ctx.respond_to?(:reader_state_reader) ? ctx.reader_state_reader : nil
          reader&.sidebar_visible? == true
        rescue StandardError
          false
        end

        def sidebar_toc_tab?(ctx)
          reader = ctx.respond_to?(:reader_state_reader) ? ctx.reader_state_reader : nil
          reader&.sidebar_active_tab == :toc
        rescue StandardError
          false
        end

        def execute_semantic_command(ctx, command_symbol, key)
          bus = resolve_command_bus(ctx)
          return :pass unless bus&.command_exists?(command_symbol)

          command = bus.build_command(command_symbol)
          return :pass unless command

          command.execute(ctx, key: key, triggered_by: :input)
        rescue StandardError
          :pass
        end

        def resolve_command_bus(ctx)
          return ctx.command_bus if ctx.respond_to?(:command_bus) && ctx.command_bus

          command_bus
        rescue StandardError
          command_bus
        end

        def dispatch_local_action(ctx, action, argument = nil)
          target = resolve_local_action_target(ctx, action)
          return :pass unless target

          invoke_action(target, action, argument)
          :handled
        rescue StandardError
          :pass
        end

        def resolve_local_action_target(ctx, action)
          return ctx if ctx.respond_to?(action)

          return nil unless ctx.respond_to?(:ui_controller)

          ui = ctx.ui_controller
          return ui if ui&.respond_to?(action)

          nil
        rescue StandardError
          nil
        end

        def invoke_action(target, action, argument = nil)
          return target.public_send(action) if argument.nil?

          target.public_send(action, argument)
        rescue ArgumentError
          target.public_send(action)
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
