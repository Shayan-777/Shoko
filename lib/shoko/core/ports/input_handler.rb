# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for handling user input.
      # Adapters implementing this interface should handle keyboard
      # and mouse input events.
      #
      # @example Implementing this port
      #   class TerminalInputHandler
      #     include Shoko::Core::Ports::InputHandler
      #
      #     def handle_key(key)
      #       # Implementation
      #     end
      #   end
      module InputHandler
        # Handle a key press event
        #
        # @param key [String] The pressed key
        # @return [Symbol] :handled if the key was processed, :pass otherwise
        def handle_key(key)
          raise NotImplementedError, "#{self.class} must implement #handle_key"
        end

        # Register key bindings for a mode
        #
        # @param mode [Symbol] The input mode (e.g., :read, :help)
        # @param bindings [Hash] Hash mapping keys to commands
        # @return [void]
        def register_mode(mode, bindings)
          raise NotImplementedError, "#{self.class} must implement #register_mode"
        end

        # Activate a specific input mode
        #
        # @param mode [Symbol] The mode to activate
        # @return [void]
        def activate_mode(mode)
          raise NotImplementedError, "#{self.class} must implement #activate_mode"
        end

        # Get the current active mode
        #
        # @return [Symbol] Current mode
        def current_mode
          raise NotImplementedError, "#{self.class} must implement #current_mode"
        end

        # Push a modal mode onto the stack
        #
        # @param mode [Symbol] The modal mode to enter
        # @return [void]
        def enter_modal(mode)
          raise NotImplementedError, "#{self.class} must implement #enter_modal"
        end

        # Pop the current modal mode from the stack
        #
        # @return [void]
        def exit_modal
          raise NotImplementedError, "#{self.class} must implement #exit_modal"
        end
      end
    end
  end
end
