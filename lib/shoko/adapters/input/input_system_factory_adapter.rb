# frozen_string_literal: true

require_relative '../../application/ports/input_system_factory'
require_relative 'reader_input_controller'
require_relative 'dispatcher'
require_relative 'annotations/mouse_handler'

module Shoko
  module Adapters::Input
    # Adapter implementing the InputSystemFactory port.
    # Creates InputController, Dispatcher, and MouseHandler instances.
    class InputSystemFactoryAdapter
      include Application::Ports::InputSystemFactory

      def create_reader_input_controller(reader_state_reader:, state_writer:, command_port:, ui_controller: nil)
        ReaderInputController.new(
          reader_state_reader: reader_state_reader,
          state_writer: state_writer,
          command_port: command_port,
          ui_controller: ui_controller
        )
      end

      def create_menu_dispatcher(context)
        Dispatcher.new(context)
      end

      def create_mouse_handler
        Annotations::MouseHandler.new
      end
    end
  end
end
