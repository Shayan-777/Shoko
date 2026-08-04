# frozen_string_literal: true

require 'shoko/adapters/support/key_definitions'

module Shoko
  module Adapters
    module Input
      # Key classification adapter for menu/input controllers.
      class KeyClassifierAdapter
        def initialize; end

        def navigation_key?(key)
          Shoko::Adapters::Support::KeyDefinitions::Helpers.navigation_key?(key)
        end

        def up_key?(key)
          Shoko::Adapters::Support::KeyDefinitions::Helpers.up_key?(key)
        end

        def down_key?(key)
          Shoko::Adapters::Support::KeyDefinitions::Helpers.down_key?(key)
        end

        def confirm_key?(key)
          Shoko::Adapters::Support::KeyDefinitions::Helpers.confirm_key?(key)
        end

        def cancel_key?(key)
          Shoko::Adapters::Support::KeyDefinitions::Helpers.cancel_key?(key)
        end

        def quit_key?(key)
          Shoko::Adapters::Support::KeyDefinitions::Helpers.quit_key?(key)
        end

        def space_key?(key)
          Shoko::Adapters::Support::KeyDefinitions::ACTIONS[:space].include?(key)
        end

        def backspace_key?(key)
          Shoko::Adapters::Support::KeyDefinitions::Helpers.backspace_key?(key)
        end

        def enter_key?(key)
          Shoko::Adapters::Support::KeyDefinitions::ACTIONS[:confirm].include?(key)
        end

        def action_keys(name)
          Shoko::Adapters::Support::KeyDefinitions::ACTIONS[name] || []
        end

        def navigation_keys(direction)
          Shoko::Adapters::Support::KeyDefinitions::NAVIGATION[direction] || []
        end
      end
    end
  end
end
