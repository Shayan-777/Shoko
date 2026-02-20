# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      # Application-facing contract for keyboard classification and key maps.
      module KeyClassifier
        def navigation_key?(key)
          raise NotImplementedError, "#{self.class} must implement #navigation_key?"
        end

        def up_key?(key)
          raise NotImplementedError, "#{self.class} must implement #up_key?"
        end

        def down_key?(key)
          raise NotImplementedError, "#{self.class} must implement #down_key?"
        end

        def confirm_key?(key)
          raise NotImplementedError, "#{self.class} must implement #confirm_key?"
        end

        def cancel_key?(key)
          raise NotImplementedError, "#{self.class} must implement #cancel_key?"
        end

        def quit_key?(key)
          raise NotImplementedError, "#{self.class} must implement #quit_key?"
        end

        def space_key?(key)
          raise NotImplementedError, "#{self.class} must implement #space_key?"
        end

        def backspace_key?(key)
          raise NotImplementedError, "#{self.class} must implement #backspace_key?"
        end

        def enter_key?(key)
          raise NotImplementedError, "#{self.class} must implement #enter_key?"
        end

        def action_keys(name)
          raise NotImplementedError, "#{self.class} must implement #action_keys"
        end

        def navigation_keys(direction)
          raise NotImplementedError, "#{self.class} must implement #navigation_keys"
        end

        def text_input_commands
          raise NotImplementedError, "#{self.class} must implement #text_input_commands"
        end
      end
    end
  end
end
