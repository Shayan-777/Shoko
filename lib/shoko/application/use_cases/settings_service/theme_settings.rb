# frozen_string_literal: true

require_relative '../../../shared/theme_policy'

module Shoko
  module Application
    module UseCases
      # Theme-related settings operations isolated from the main service body.
      module SettingsServiceThemeSettings
        # Cycle through canonical reader theme options and persist the change.
        def cycle_theme
          themes = Shoko::Shared::ThemePolicy.canonical_ids
          current = Shoko::Shared::ThemePolicy.normalize(@app_config_store.load.theme) ||
                    Shoko::Shared::ThemePolicy.default_id
          current_index = themes.index(current) || 0
          next_theme = themes[(current_index + 1) % themes.length]
          dispatch_config(theme: next_theme)
          next_theme
        end

        # Set explicit theme after validating against canonical theme registry.
        # rubocop:disable Naming/AccessorMethodName
        def set_theme(theme_id)
          canonical = Shoko::Shared::ThemePolicy.normalize(theme_id)
          raise ArgumentError, "Unsupported theme: #{theme_id.inspect}" unless canonical

          dispatch_config(theme: canonical)
          canonical
        end
        # rubocop:enable Naming/AccessorMethodName
      end
    end
  end
end
