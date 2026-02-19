# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      # Application-facing contract for creating input system components.
      module InputSystemFactory
        def create_reader_input_controller(reader_state_reader:, state_writer:, command_port:, ui_controller: nil)
          raise NotImplementedError, "#{self.class} must implement #create_reader_input_controller"
        end

        def create_menu_dispatcher(context)
          raise NotImplementedError, "#{self.class} must implement #create_menu_dispatcher"
        end

        def create_mouse_handler
          raise NotImplementedError, "#{self.class} must implement #create_mouse_handler"
        end
      end
    end
  end
end
