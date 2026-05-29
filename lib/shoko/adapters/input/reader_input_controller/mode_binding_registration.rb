# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      class ReaderInputController
        # Registers popup/help/modal reader input bindings outside the controller body.
        module ModeBindingRegistration
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

          def setup_consolidated_reader_bindings
            register_read_bindings
            register_popup_menu_bindings
            register_help_bindings
            register_library_bindings
            register_dictionary_bindings
            register_in_book_search_bindings
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
            bind_intent!(bindings, Shoko::Shared::KeyDefinitions::ACTIONS[:confirm], :edit_annotation_text,
                         payload: edit_op(:newline))
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
        end
      end
    end
  end
end
