# frozen_string_literal: true

require_relative 'base_action'
require_relative '../../../../shared/theme_policy'

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
                if config_field == :theme
                  canonical_theme = Shoko::Shared::ThemePolicy.normalize(value)
                  value = canonical_theme || value
                end
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
