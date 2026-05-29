# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Re-activates the menu input dispatcher when `state[:menu][:mode]` changes.
          # Replaces the imperative MenuModeControl#activate_menu_mode round-trip
          # that application use cases previously emitted alongside the state write.
          class InputModeObserver
            OBSERVED_PATHS = [%i[menu mode]].freeze

            def initialize(input_controller:, logger: nil)
              @input_controller = input_controller
              @logger = logger
            end

            def observed_paths
              OBSERVED_PATHS
            end

            def state_changed(path, _old_value, new_value)
              return unless path == %i[menu mode]
              return if new_value.nil?

              @input_controller.activate(new_value)
            rescue Shoko::Error => e
              @logger&.debug('menu.input_mode_observer.activate_failed',
                             mode: new_value,
                             error: e.class.name,
                             message: e.message)
            end
          end
        end
      end
    end
  end
end
