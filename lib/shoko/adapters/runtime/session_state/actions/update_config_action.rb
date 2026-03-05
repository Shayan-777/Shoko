# frozen_string_literal: true

require_relative 'base_action'
require_relative '../../../ui/constants/themes'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        module Actions
          # Action for updating configuration values
          class UpdateConfigAction < BaseAction
            def initialize(**updates)
              super(updates)
            end

            def apply(state)
              # Build update hash for atomic state update
              updates = {}
              payload.each do |config_field, value|
                value = Shoko::Adapters::Ui::Constants::Themes.normalize_theme(value) if config_field == :theme
                updates[[:config, config_field]] = value
              end
              state.update(updates)
              state.save_config
            end
          end
        end
      end
    end
  end
end
