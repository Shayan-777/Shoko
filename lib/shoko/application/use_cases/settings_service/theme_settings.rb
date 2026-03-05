# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      # Theme-related settings operations isolated from the main service body.
      module SettingsServiceThemeSettings
        THEME_SEQUENCE = %i[default gray sepia grass cherry sky solarized gruvbox nord].freeze
        THEME_ALIASES = {
          dark: :default,
          light: :gray,
        }.freeze

        # Cycle through canonical reader theme options and persist the change.
        def cycle_theme
          themes = THEME_SEQUENCE
          current = normalize_theme(@config_reader.theme) || :default
          current_index = themes.index(current) || 0
          next_theme = themes[(current_index + 1) % themes.length]
          dispatch_config(theme: next_theme)
          next_theme
        end

        # Set explicit theme after validating against canonical theme registry.
        # rubocop:disable Naming/AccessorMethodName
        def set_theme(theme_id)
          canonical = normalize_theme(theme_id)
          raise ArgumentError, "Unsupported theme: #{theme_id.inspect}" unless canonical

          dispatch_config(theme: canonical)
          canonical
        end
        # rubocop:enable Naming/AccessorMethodName

        private

        def normalize_theme(value)
          return nil if value.nil?

          key = value.is_a?(Symbol) ? value : value.to_s.strip.downcase.to_sym
          canonical = THEME_ALIASES.fetch(key, key)
          return canonical if THEME_SEQUENCE.include?(canonical)

          nil
        end
      end
    end
  end
end
