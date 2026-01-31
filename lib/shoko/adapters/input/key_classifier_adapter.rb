# frozen_string_literal: true

require_relative '../../core/ports/key_classifier'
require_relative 'key_definitions'

module Shoko
  module Adapters::Input
    # Adapter implementing the KeyClassifier port.
    # Delegates to KeyDefinitions constants for key classification.
    class KeyClassifierAdapter
      include Core::Ports::KeyClassifier

      def initialize(command_factory: nil)
        @command_factory = command_factory
      end

      def navigation_key?(key)
        KeyDefinitions::Helpers.navigation_key?(key)
      end

      def up_key?(key)
        KeyDefinitions::Helpers.up_key?(key)
      end

      def down_key?(key)
        KeyDefinitions::Helpers.down_key?(key)
      end

      def confirm_key?(key)
        KeyDefinitions::Helpers.confirm_key?(key)
      end

      def cancel_key?(key)
        KeyDefinitions::Helpers.cancel_key?(key)
      end

      def quit_key?(key)
        KeyDefinitions::Helpers.quit_key?(key)
      end

      def space_key?(key)
        KeyDefinitions::ACTIONS[:space].include?(key)
      end

      def backspace_key?(key)
        KeyDefinitions::Helpers.backspace_key?(key)
      end

      def enter_key?(key)
        KeyDefinitions::ACTIONS[:confirm].include?(key)
      end

      def action_keys(name)
        KeyDefinitions::ACTIONS[name] || []
      end

      def navigation_keys(direction)
        KeyDefinitions::NAVIGATION[direction] || []
      end

      def text_input_commands
        @command_factory
      end
    end
  end
end
