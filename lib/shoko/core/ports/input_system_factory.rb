# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for creating input system components.
      # Adapters implementing this interface should handle instantiation
      # of input controllers, dispatchers, and mouse handlers.
      module InputSystemFactory
        # Create an input controller for the reader view
        #
        # @param state [Object] Application state
        # @param reader_state_reader [Object] Reader state reader port
        # @param state_writer [Object] State writer port
        # @param command_port [Object] Command port for symbol-to-command mapping
        # @param ui_controller [Object, nil] Reader UI controller
        # @return [Object] Input controller instance
        def create_reader_input_controller(state, reader_state_reader:, state_writer:, command_port:, ui_controller: nil)
          raise NotImplementedError, "#{self.class} must implement #create_reader_input_controller"
        end

        # Create a command dispatcher for the menu view
        #
        # @param context [Object] Menu context
        # @return [Object] Dispatcher instance
        def create_menu_dispatcher(context)
          raise NotImplementedError, "#{self.class} must implement #create_menu_dispatcher"
        end

        # Create a mouse handler for annotations and selection
        #
        # @return [Object] Mouse handler instance
        def create_mouse_handler
          raise NotImplementedError, "#{self.class} must implement #create_mouse_handler"
        end
      end
    end
  end
end
