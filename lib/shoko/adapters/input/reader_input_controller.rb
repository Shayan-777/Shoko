# frozen_string_literal: true

require_relative '../../shared/key_definitions'
require_relative '../../shared/text_sanitizer'
require_relative '../../application/use_cases/requests/text_input'
require_relative '../../application/use_cases/requests/selection_delta'
require_relative '../../application/use_cases/requests/cursor_move'
require_relative 'intent_binding'

module Shoko
  module Adapters
    module Input
      # Handles all input processing: key handling, popup management, mode switching
      class ReaderInputController
        ANNOTATION_EDITOR_SPELLCHECK_KEYS = ["\ed", "\eD"].freeze

        def initialize(reader_state_reader:, ui_controller: nil,
                       ui_controller_provider: nil)
          @ui_controller = ui_controller
          @ui_controller_provider = ui_controller_provider
          @dispatcher = nil
          @modal_mode_stack = []
          @reader_state_reader = reader_state_reader
        end

        def setup_input_dispatcher(reader_intent_handler)
          @dispatcher = Adapters::Input::Dispatcher.new(
            intent_dispatcher: lambda { |intent, payload|
              reader_intent_handler.handle_reader_intent(intent, payload)
            }
          )
          setup_consolidated_reader_bindings
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
          return @ui_controller_provider.call if @ui_controller_provider

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

        def setup_consolidated_reader_bindings
          register_read_bindings
          register_popup_menu_bindings

          # Register non-read modes expected by reader state transitions.
          register_help_bindings
          register_library_bindings
          register_dictionary_bindings
          register_in_book_search_bindings
          register_annotation_editor_bindings
        end

        def register_read_bindings
          bindings = {}
          bindings.merge!(reader_navigation_bindings)
          bindings.merge!(read_mode_local_bindings)

          @dispatcher.register_mode(:read, bindings)
        end

        def register_popup_menu_bindings
          bindings = {}
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::NAVIGATION[:up], :popup_move_up,
                       payload: selection_delta(-1))
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::NAVIGATION[:down], :popup_move_down,
                       payload: selection_delta(1))
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:confirm], :popup_confirm)
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:cancel], :popup_cancel)
          @dispatcher.register_mode(:popup_menu, bindings)
        end

        def register_help_bindings
          bindings = { __default__: IntentBinding.new(:close_help_overlay) }
          @dispatcher.register_mode(:help, bindings)
        end

        def register_library_bindings
          # Keys are registered in MainMenu#register_library_bindings; this hook ensures mode exists
          # No-op here as dispatcher registration happens in MainMenu.
        end

        def register_annotation_editor_bindings
          bindings = {}

          bind_intent!(bindings, ["\e"], :annotation_editor_cancel)

          # Save: Ctrl+S and 'S'
          save_keys = Shoko::Shared::KeyDefinitions::ACTIONS[:save] || []
          bind_intent!(bindings, save_keys, :annotation_editor_save)
          bind_intent!(bindings, ANNOTATION_EDITOR_SPELLCHECK_KEYS, :annotation_editor_spellcheck)

          # Backspace (both variants)
          bind_intent!(bindings, ["\x7F", "\b"], :annotation_editor_backspace)

          # Enter (CR and LF)
          confirm_keys = Shoko::Shared::KeyDefinitions::ACTIONS[:confirm]
          bind_intent!(bindings, confirm_keys, :annotation_editor_newline)

          # Cursor movement
          arrow_keys = ->(keys) { keys.select { |k| k.to_s.start_with?("\e") } }
          arrow_keys.call(Shoko::Shared::KeyDefinitions::NAVIGATION[:left]).each do |k|
            bindings[k] = IntentBinding.new(:annotation_editor_move_left, payload: cursor_move(:left))
          end
          arrow_keys.call(Shoko::Shared::KeyDefinitions::NAVIGATION[:right]).each do |k|
            bindings[k] = IntentBinding.new(:annotation_editor_move_right, payload: cursor_move(:right))
          end
          arrow_keys.call(Shoko::Shared::KeyDefinitions::NAVIGATION[:up]).each do |k|
            bindings[k] = IntentBinding.new(:annotation_editor_move_up, payload: cursor_move(:up))
          end
          arrow_keys.call(Shoko::Shared::KeyDefinitions::NAVIGATION[:down]).each do |k|
            bindings[k] = IntentBinding.new(:annotation_editor_move_down, payload: cursor_move(:down))
          end

          bindings[:__default__] = text_input_binding(:annotation_editor_insert_text)

          @dispatcher.register_mode(:annotation_editor, bindings)
        end

        def register_dictionary_bindings
          bindings = {}

          # Close dictionary with Escape or q
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:cancel], :close_dictionary)
          bind_intent!(bindings, ['q'], :close_dictionary)

          # Navigation - scroll up/down
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::NAVIGATION[:up], :dictionary_move_up,
                       payload: selection_delta(-1))
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::NAVIGATION[:down], :dictionary_move_down,
                       payload: selection_delta(1))

          bind_intent!(bindings, ['f'], :dictionary_toggle_fuzzy)
          bind_intent!(bindings, ["\t"], :dictionary_cycle_result)
          bind_intent!(bindings, ['S'], :dictionary_swap_languages)
          bind_intent!(bindings, ['L'], :dictionary_cycle_pair)
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:confirm], :dictionary_confirm)
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:backspace], :dictionary_backspace)
          bindings[:__default__] = text_input_binding(:dictionary_insert_text)

          @dispatcher.register_mode(:dictionary, bindings)
        end

        def register_in_book_search_bindings
          bindings = {}

          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:cancel], :close_in_book_search)

          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::NAVIGATION[:up], :search_move_up,
                       payload: selection_delta(-1))
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::NAVIGATION[:down], :search_move_down,
                       payload: selection_delta(1))

          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:confirm], :search_confirm)
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:backspace], :search_backspace)

          bindings[:__default__] = text_input_binding(:search_insert_text)

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

          bind_intent!(bindings, reader[:toggle_view], :toggle_view_mode)
          bind_intent!(bindings, reader[:toggle_page_mode], :toggle_page_numbering_mode)
          bind_intent!(bindings, reader[:increase_spacing], :increase_line_spacing)
          bind_intent!(bindings, reader[:decrease_spacing], :decrease_line_spacing)
          bind_intent!(bindings, reader[:show_toc], :open_toc_sidebar)
          bind_intent!(bindings, reader[:show_bookmarks], :open_bookmarks_sidebar)
          if reader.key?(:show_annotations_tab)
            bind_intent!(bindings, reader[:show_annotations_tab], :open_annotations_sidebar)
          end
          bind_intent!(bindings, reader[:show_annotations], :open_annotations_overlay) if reader.key?(:show_annotations)
          bind_intent!(bindings, reader[:in_book_search], :open_in_book_search) if reader.key?(:in_book_search)
          bind_intent!(bindings, reader[:show_help], :open_help_overlay)
          bind_intent!(bindings, reader[:rebuild_pagination], :rebuild_pagination) if reader.key?(:rebuild_pagination)
          if reader.key?(:invalidate_pagination)
            bind_intent!(bindings, reader[:invalidate_pagination], :clear_pagination_cache)
          end

          bind_intent!(bindings, reader[:add_bookmark], :add_bookmark)
          bind_intent!(bindings, actions[:quit], :quit_to_menu)
          bind_intent!(bindings, actions[:force_quit], :quit_application)
          bindings
        end

        def reader_navigation_bindings
          reader = Shoko::Shared::KeyDefinitions::READER
          bindings = {}

          bind_intent!(bindings, reader[:next_page], :next_page)
          bind_intent!(bindings, reader[:prev_page], :prev_page)
          bind_intent!(bindings, reader[:next_chapter], :next_chapter)
          bind_intent!(bindings, reader[:prev_chapter], :prev_chapter)
          bind_intent!(bindings, reader[:go_to_start], :go_to_start)
          bind_intent!(bindings, reader[:go_to_end], :go_to_end)

          bind_dynamic_intent!(bindings, Shoko::Shared::KeyDefinitions::NAVIGATION[:down]) do
            if reader_state_reader&.sidebar_visible?
              IntentBinding.new(:sidebar_move_down, payload: selection_delta(1))
            else
              IntentBinding.new(:scroll_down)
            end
          end

          bind_dynamic_intent!(bindings, Shoko::Shared::KeyDefinitions::NAVIGATION[:up]) do
            if reader_state_reader&.sidebar_visible?
              IntentBinding.new(:sidebar_move_up, payload: selection_delta(-1))
            else
              IntentBinding.new(:scroll_up)
            end
          end

          bind_dynamic_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:confirm]) do
            if reader_state_reader&.sidebar_visible?
              IntentBinding.new(:sidebar_activate)
            else
              IntentBinding.new(:next_page)
            end
          end

          bind_dynamic_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:space]) do
            if reader_state_reader&.sidebar_visible? && reader_state_reader&.sidebar_active_tab == :toc
              IntentBinding.new(:toggle_sidebar)
            else
              IntentBinding.new(:next_page)
            end
          end

          bindings
        end

        def bind_intent!(bindings, keys, intent, payload: nil)
          binding = IntentBinding.new(intent, payload: payload)
          Array(keys).each { |key| bindings[key] = binding }
          bindings
        end

        def bind_dynamic_intent!(bindings, keys, &resolver)
          binding = DynamicIntentBinding.new do |key|
            instance_exec(key, &resolver)
          end
          Array(keys).each { |key| bindings[key] = binding }
          bindings
        end

        def text_input_binding(intent)
          IntentBinding.new(intent) do |key|
            char = key.to_s
            if Shoko::Shared::TextSanitizer.printable_char?(char)
              Shoko::Application::UseCases::Requests::TextInput.new(text: char)
            else
              IntentBinding.skip
            end
          end
        end

        def selection_delta(delta)
          Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: delta)
        end

        def cursor_move(direction)
          Shoko::Application::UseCases::Requests::CursorMove.new(direction: direction)
        end

        def reader_state_reader
          @reader_state_reader
        end

        # Removed reader annotations list bindings; annotations are managed via the sidebar
      end
    end
  end
end
