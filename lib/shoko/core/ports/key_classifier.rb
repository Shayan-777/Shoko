# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for classifying keyboard input.
      # Adapters implementing this interface should handle mapping raw key
      # codes to semantic actions (navigation, confirmation, cancellation, etc.).
      module KeyClassifier
        # Check if the key is any navigation key (up, down, left, right, etc.)
        #
        # @param key [String] The pressed key
        # @return [Boolean]
        def navigation_key?(key)
          raise NotImplementedError, "#{self.class} must implement #navigation_key?"
        end

        # Check if the key is an up-navigation key
        #
        # @param key [String] The pressed key
        # @return [Boolean]
        def up_key?(key)
          raise NotImplementedError, "#{self.class} must implement #up_key?"
        end

        # Check if the key is a down-navigation key
        #
        # @param key [String] The pressed key
        # @return [Boolean]
        def down_key?(key)
          raise NotImplementedError, "#{self.class} must implement #down_key?"
        end

        # Check if the key is a confirm/enter key
        #
        # @param key [String] The pressed key
        # @return [Boolean]
        def confirm_key?(key)
          raise NotImplementedError, "#{self.class} must implement #confirm_key?"
        end

        # Check if the key is a cancel/escape key
        #
        # @param key [String] The pressed key
        # @return [Boolean]
        def cancel_key?(key)
          raise NotImplementedError, "#{self.class} must implement #cancel_key?"
        end

        # Check if the key is a quit key
        #
        # @param key [String] The pressed key
        # @return [Boolean]
        def quit_key?(key)
          raise NotImplementedError, "#{self.class} must implement #quit_key?"
        end

        # Check if the key is a space key
        #
        # @param key [String] The pressed key
        # @return [Boolean]
        def space_key?(key)
          raise NotImplementedError, "#{self.class} must implement #space_key?"
        end

        # Check if the key is a backspace key
        #
        # @param key [String] The pressed key
        # @return [Boolean]
        def backspace_key?(key)
          raise NotImplementedError, "#{self.class} must implement #backspace_key?"
        end

        # Check if the key is an enter key
        #
        # @param key [String] The pressed key
        # @return [Boolean]
        def enter_key?(key)
          raise NotImplementedError, "#{self.class} must implement #enter_key?"
        end

        # Get all key codes mapped to a named action
        #
        # @param name [Symbol] Action name (e.g. :quit, :confirm, :cancel, :space, :backspace, :enter)
        # @return [Array<String>] Array of key codes for the action
        def action_keys(name)
          raise NotImplementedError, "#{self.class} must implement #action_keys"
        end

        # Get all key codes mapped to a navigation direction
        #
        # @param direction [Symbol] Direction (e.g. :up, :down)
        # @return [Array<String>] Array of key codes for the direction
        def navigation_keys(direction)
          raise NotImplementedError, "#{self.class} must implement #navigation_keys"
        end

        # Get the set of key values considered text input commands
        #
        # @return [Array, Set] Collection of text-input key values
        def text_input_commands
          raise NotImplementedError, "#{self.class} must implement #text_input_commands"
        end
      end
    end
  end
end
