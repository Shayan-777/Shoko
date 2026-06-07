# frozen_string_literal: true

require_relative '../../shared/key_definitions'
require_relative '../../shared/text_sanitizer'
require_relative '../../application/use_cases/requests/text_input'
require_relative '../../application/use_cases/requests/edit_op'
require_relative '../../application/use_cases/requests/selection_delta'
require_relative '../../application/use_cases/requests/cursor_move'
require_relative 'intent_binding'

module Shoko
  module Adapters
    module Input
      # Handles all input processing: key handling, popup management, mode switching
      class ReaderInputController
        ANNOTATION_EDITOR_SPELLCHECK_KEYS = ["\ed", "\eD"].freeze
        TRANSLATOR_HOME_KEYS = ["\e[H", "\e[1~", "\eOH", "\x01"].freeze # Home / Ctrl+A
        TRANSLATOR_END_KEYS = ["\e[F", "\e[4~", "\eOF", "\x05"].freeze  # End / Ctrl+E
        TRANSLATOR_DELETE_KEYS = ["\e[3~"].freeze                        # forward Delete
        # Newline (write a list, etc.) while Enter stays "translate". Shift+Enter is
        # only distinct on terminals that report modified keys (the CSI-27 / CSI-u
        # forms, modifier 2); Alt+Enter (ESC+CR/LF, or modifier 3) is the reliable
        # fallback that every terminal sends — matching the menu translator.
        TRANSLATOR_NEWLINE_KEYS = [
          "\e[27;2;13~", "\e[13;2u",            # Shift+Enter
          "\e\r", "\e\n", "\e[27;3;13~", "\e[13;3u" # Alt+Enter
        ].freeze

        def initialize(reader_state_reader:, ui_controller: nil,
                       ui_controller_provider: nil)
          @ui_controller = ui_controller
          @ui_controller_provider = ui_controller_provider
          @dispatcher = nil
          @modal_mode_stack = []
          @reader_state_reader = reader_state_reader
        end

        def setup_input_dispatcher(reader_intent_handler)
          @reader_intent_handler = reader_intent_handler
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

        # Dispatch a known reader intent directly (bypassing key bindings).
        # Used by adapter controllers that must re-enter the use-case layer,
        # e.g. routing the popup "Look Up" action through the dictionary use case.
        def dispatch_reader_intent(intent, payload = nil)
          @reader_intent_handler&.handle_reader_intent(intent, payload)
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
          when :toc
            @dispatcher.activate(:toc)
          when :translator
            @dispatcher.activate(:translator)
          else
            @dispatcher.activate_stack([:read])
          end
        end

        def enter_modal_mode(mode)
          return unless @dispatcher

          current_stack = @dispatcher.mode_stack
          return if current_stack.last == mode

          @modal_mode_stack << current_stack
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

        def bind_intent!(bindings, keys, intent, payload: nil)
          binding = IntentBinding.new(intent, payload: payload)
          Array(keys).each { |key| bindings[key] = binding }
          bindings
        end

        def bind_dynamic_intent!(bindings, keys, &)
          binding = DynamicIntentBinding.new do |key|
            instance_exec(key, &)
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

        def edit_op_text_binding(intent)
          IntentBinding.new(intent) do |key|
            char = key.to_s
            if Shoko::Shared::TextSanitizer.printable_char?(char)
              Shoko::Application::UseCases::Requests::EditOp.new(operation: :insert, text: char)
            else
              IntentBinding.skip
            end
          end
        end

        def edit_op(operation)
          Shoko::Application::UseCases::Requests::EditOp.new(operation: operation)
        end

        def selection_delta(delta)
          Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: delta)
        end

        def cursor_move(direction)
          Shoko::Application::UseCases::Requests::CursorMove.new(direction: direction)
        end

        attr_reader :reader_state_reader


        def setup_consolidated_reader_bindings
          register_read_bindings
          register_popup_menu_bindings
          register_help_bindings
          register_library_bindings
          register_dictionary_bindings
          register_in_book_search_bindings
          register_toc_bindings
          register_translator_bindings
          register_annotation_editor_bindings
        end

        def register_popup_menu_bindings
          bindings = {}
          bind_intent!(bindings,
                       Shoko::Shared::KeyDefinitions::NAVIGATION[:up],
                       :popup_move_up,
                       payload: selection_delta(-1))
          bind_intent!(bindings,
                       Shoko::Shared::KeyDefinitions::NAVIGATION[:down],
                       :popup_move_down,
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
          nil
        end

        def register_annotation_editor_bindings
          bindings = {}
          bind_annotation_editor_controls(bindings)
          bind_annotation_editor_movements(bindings)
          bindings[:__default__] = edit_op_text_binding(:edit_annotation_text)
          @dispatcher.register_mode(:annotation_editor, bindings)
        end

        def bind_annotation_editor_controls(bindings)
          bind_intent!(bindings, ["\e"], :annotation_editor_cancel)
          save_keys = Shoko::Shared::KeyDefinitions::ACTIONS[:save] || []
          bind_intent!(bindings, save_keys, :annotation_editor_save)
          bind_intent!(
            bindings,
            ReaderInputController::ANNOTATION_EDITOR_SPELLCHECK_KEYS,
            :annotation_editor_spellcheck
          )
          bind_intent!(bindings, ["\x7F", "\b"], :edit_annotation_text, payload: edit_op(:backspace))
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:confirm], :annotation_editor_confirm)
        end

        def bind_annotation_editor_movements(bindings)
          %i[left right up down].each do |direction|
            filter_arrow_keys(Shoko::Shared::KeyDefinitions::NAVIGATION[direction]).each do |key|
              bindings[key] = IntentBinding.new(:move_annotation_cursor, payload: cursor_move(direction))
            end
          end
        end

        def filter_arrow_keys(keys)
          Array(keys).select { |key| key.to_s.start_with?("\e") }
        end

        def register_dictionary_bindings
          bindings = {}
          bind_dictionary_controls(bindings)
          bind_dictionary_navigation(bindings)
          bindings[:__default__] = edit_op_text_binding(:edit_reader_dictionary_query)
          @dispatcher.register_mode(:dictionary, bindings)
        end

        def bind_dictionary_controls(bindings)
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:cancel], :close_dictionary)
          bind_intent!(bindings, ['q'], :close_dictionary)
          bind_intent!(bindings, ['f'], :dictionary_toggle_fuzzy)
          bind_intent!(bindings, ["\t"], :dictionary_cycle_result)
          bind_intent!(bindings, ['S'], :dictionary_swap_languages)
          bind_intent!(bindings, ['L'], :dictionary_cycle_pair)
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:confirm], :dictionary_confirm)
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:backspace], :edit_reader_dictionary_query,
                       payload: edit_op(:backspace))
        end

        def bind_dictionary_navigation(bindings)
          bind_intent!(bindings,
                       Shoko::Shared::KeyDefinitions::NAVIGATION[:up],
                       :dictionary_move_up,
                       payload: selection_delta(-1))
          bind_intent!(bindings,
                       Shoko::Shared::KeyDefinitions::NAVIGATION[:down],
                       :dictionary_move_down,
                       payload: selection_delta(1))
        end

        def register_in_book_search_bindings
          bindings = {}
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:cancel], :close_in_book_search)
          bind_intent!(bindings,
                       Shoko::Shared::KeyDefinitions::NAVIGATION[:up],
                       :search_move_up,
                       payload: selection_delta(-1))
          bind_intent!(bindings,
                       Shoko::Shared::KeyDefinitions::NAVIGATION[:down],
                       :search_move_down,
                       payload: selection_delta(1))
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:confirm], :search_confirm)
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:backspace], :edit_in_book_search,
                       payload: edit_op(:backspace))
          bindings[:__default__] = edit_op_text_binding(:edit_in_book_search)
          @dispatcher.register_mode(:in_book_search, bindings)
        end

        # The TOC bar is a live chapter filter, so it stays a text-input mode: only
        # the arrow-key escape sequences move the selection (not the j/k letter
        # aliases), keeping every printable key — including h/j/k/l — free to type
        # into the filter. Mirrors the annotation editor's arrow-only movement.
        def register_toc_bindings
          bindings = {}
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:cancel], :close_toc)
          bind_intent!(bindings,
                       filter_arrow_keys(Shoko::Shared::KeyDefinitions::NAVIGATION[:up]),
                       :toc_move_up,
                       payload: selection_delta(-1))
          bind_intent!(bindings,
                       filter_arrow_keys(Shoko::Shared::KeyDefinitions::NAVIGATION[:down]),
                       :toc_move_down,
                       payload: selection_delta(1))
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:confirm], :toc_confirm)
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:backspace], :edit_toc_filter,
                       payload: edit_op(:backspace))
          bindings[:__default__] = edit_op_text_binding(:edit_toc_filter)
          @dispatcher.register_mode(:toc, bindings)
        end

        # The translator source editor is a free-form multi-line text field (and, with
        # the picker open, a language filter), so — like the TOC filter — it stays a
        # text-input mode: only the arrow-key escape sequences move the caret/selection
        # (not the h/j/k/l letter aliases), keeping every printable key free to type.
        # ←/→/Home/End move the caret (or flip the picker side); ↑/↓ scroll the
        # translation (or move the picker selection); Enter translates; Tab cycles the
        # language picker; Shift+Tab swaps the pair; Delete forward-deletes.
        def register_translator_bindings
          bindings = {}
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:cancel], :close_translator)
          bind_translator_caret_keys(bindings)
          bind_intent!(bindings, ["\t"], :translator_cycle_picker)
          bind_intent!(bindings, ["\e[Z"], :translator_swap_languages)
          bind_intent!(bindings, TRANSLATOR_NEWLINE_KEYS, :edit_translator, payload: edit_op(:newline))
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:confirm], :translator_confirm)
          bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:backspace], :edit_translator,
                       payload: edit_op(:backspace))
          bind_intent!(bindings, TRANSLATOR_DELETE_KEYS, :edit_translator, payload: edit_op(:delete))
          bindings[:__default__] = edit_op_text_binding(:edit_translator)
          @dispatcher.register_mode(:translator, bindings)
        end

        def bind_translator_caret_keys(bindings)
          %i[left right up down].each do |direction|
            keys = filter_arrow_keys(Shoko::Shared::KeyDefinitions::NAVIGATION[direction])
            bind_intent!(bindings, keys, :translator_cursor_move, payload: cursor_move(direction))
          end
          bind_intent!(bindings, TRANSLATOR_HOME_KEYS, :translator_cursor_move, payload: cursor_move(:home))
          bind_intent!(bindings, TRANSLATOR_END_KEYS, :translator_cursor_move, payload: cursor_move(:end))
        end


        def register_read_bindings
          bindings = {}
          bindings.merge!(reader_navigation_bindings)
          bindings.merge!(read_mode_local_bindings)
          @dispatcher.register_mode(:read, bindings)
        end

        def read_mode_local_bindings
          reader = Shoko::Shared::KeyDefinitions::READER
          actions = Shoko::Shared::KeyDefinitions::ACTIONS
          bindings = {}
          bind_reader_display_controls(bindings, reader)
          bind_reader_sidebar_controls(bindings, reader)
          bind_reader_session_controls(bindings, reader, actions)
          bindings
        end

        def bind_reader_display_controls(bindings, reader)
          bind_intent!(bindings, reader[:toggle_view], :toggle_view_mode)
          bind_intent!(bindings, reader[:toggle_page_mode], :toggle_page_numbering_mode)
          bind_intent!(bindings, reader[:increase_spacing], :increase_line_spacing)
          bind_intent!(bindings, reader[:decrease_spacing], :decrease_line_spacing)
          bind_intent!(bindings, reader[:show_help], :open_help_overlay)
          bind_intent!(bindings, reader[:rebuild_pagination], :rebuild_pagination) if reader.key?(:rebuild_pagination)
          bind_optional_reader_action(bindings, reader, :invalidate_pagination, :clear_pagination_cache)
        end

        def bind_reader_sidebar_controls(bindings, reader)
          bind_intent!(bindings, reader[:show_toc], :open_toc)
          bind_intent!(bindings, reader[:show_bookmarks], :open_bookmarks_sidebar)
          bind_optional_reader_action(bindings, reader, :show_annotations_tab, :open_annotations_sidebar)
          bind_optional_reader_action(bindings, reader, :show_annotations, :open_annotations_overlay)
          bind_optional_reader_action(bindings, reader, :in_book_search, :open_in_book_search)
          bind_optional_reader_action(bindings, reader, :dictionary, :open_dictionary)
          bind_optional_reader_action(bindings, reader, :translator, :open_translator)
        end

        def bind_reader_session_controls(bindings, reader, actions)
          bind_intent!(bindings, reader[:add_bookmark], :add_bookmark)
          bind_intent!(bindings, actions[:quit], :quit_to_menu)
          bind_intent!(bindings, actions[:force_quit], :quit_application)
        end

        def reader_navigation_bindings
          reader = Shoko::Shared::KeyDefinitions::READER
          bindings = {}
          bind_static_reader_navigation!(bindings, reader)
          bind_sidebar_aware_reader_navigation!(bindings)
          bindings
        end

        def bind_static_reader_navigation!(bindings, reader)
          bind_intent!(bindings, reader[:next_page], :next_page)
          bind_intent!(bindings, reader[:prev_page], :prev_page)
          bind_intent!(bindings, reader[:next_chapter], :next_chapter)
          bind_intent!(bindings, reader[:prev_chapter], :prev_chapter)
          bind_intent!(bindings, reader[:go_to_start], :go_to_start)
          bind_intent!(bindings, reader[:go_to_end], :go_to_end)
        end

        def bind_sidebar_aware_reader_navigation!(bindings)
          bind_sidebar_move_down!(bindings)
          bind_sidebar_move_up!(bindings)
          bind_sidebar_aware_action!(bindings, :confirm) do
            sidebar_visible? ? IntentBinding.new(:sidebar_activate) : IntentBinding.new(:next_page)
          end
          bind_sidebar_aware_action!(bindings, :space) do
            sidebar_toc_active? ? IntentBinding.new(:toggle_sidebar) : IntentBinding.new(:next_page)
          end
        end

        def bind_sidebar_aware_action!(bindings, key, &)
          bind_dynamic_intent!(bindings, sidebar_navigation_keyset(key), &)
        end

        def sidebar_navigation_keyset(key)
          case key
          when :confirm, :space then Shoko::Shared::KeyDefinitions::ACTIONS[key]
          else Shoko::Shared::KeyDefinitions::NAVIGATION[key]
          end
        end

        def sidebar_visible?
          reader_state_reader&.sidebar_visible?
        end

        def sidebar_toc_active?
          sidebar_visible? && reader_state_reader&.sidebar_active_tab == :toc
        end

        def bind_sidebar_move_down!(bindings)
          bind_sidebar_aware_action!(bindings, :down) do
            sidebar_visible? ? sidebar_move_binding(1) : IntentBinding.new(:scroll_down)
          end
        end

        def bind_sidebar_move_up!(bindings)
          bind_sidebar_aware_action!(bindings, :up) do
            sidebar_visible? ? sidebar_move_binding(-1) : IntentBinding.new(:scroll_up)
          end
        end

        def sidebar_move_binding(delta)
          intent = delta.positive? ? :sidebar_move_down : :sidebar_move_up
          IntentBinding.new(intent, payload: selection_delta(delta))
        end

        def bind_optional_reader_action(bindings, reader, key, intent)
          return unless reader.key?(key)

          bind_intent!(bindings, reader[key], intent)
        end

      end
    end
  end
end
