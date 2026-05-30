# frozen_string_literal: true

require_relative '../../shared/key_definitions'
require_relative '../../shared/text_sanitizer'
require_relative '../../application/use_cases/requests/text_input'
require_relative '../../application/use_cases/requests/edit_op'
require_relative '../../application/use_cases/requests/selection_delta'
require_relative '../../application/use_cases/requests/cursor_move'
require_relative 'intent_binding'
require_relative 'reader_input_controller/mode_binding_registration'
require_relative 'reader_input_controller/read_mode_binding_registration'

module Shoko
  module Adapters
    module Input
      # Handles all input processing: key handling, popup management, mode switching
      class ReaderInputController
        ANNOTATION_EDITOR_SPELLCHECK_KEYS = ["\ed", "\eD"].freeze
        include ModeBindingRegistration
        include ReadModeBindingRegistration

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
      end
    end
  end
end
