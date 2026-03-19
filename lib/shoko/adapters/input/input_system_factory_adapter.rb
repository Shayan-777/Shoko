# frozen_string_literal: true

require_relative 'reader_input_controller'
require_relative 'dispatcher'
require_relative 'annotations/mouse_handler'

module Shoko
  module Adapters
    module Input
      # Factory for input-side controller/dispatcher instances.
      class InputSystemFactoryAdapter
        def create_reader_input_controller(reader_state_reader:, ui_controller: nil,
                                           ui_controller_provider: nil)
          ReaderInputController.new(
            reader_state_reader: reader_state_reader,
            ui_controller: ui_controller,
            ui_controller_provider: ui_controller_provider
          )
        end

        def create_menu_dispatcher(intent_handler:)
          Dispatcher.new(intent_dispatcher: lambda { |intent, payload|
            intent_handler.handle_menu_intent(intent, payload)
          })
        end

        def create_mouse_handler
          Annotations::MouseHandler.new
        end
      end
    end
  end
end
