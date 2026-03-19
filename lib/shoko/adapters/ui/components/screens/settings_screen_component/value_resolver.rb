# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Value-resolution helpers for the settings list and inspector summary.
          module SettingsScreenComponentValueResolver
            PREFERENCE_VALUE_HELPERS = {
              toggle_view_mode: :view_mode_value,
              cycle_line_spacing: :line_spacing_value,
              cycle_download_source: :download_source_value,
              cycle_theme: :theme_value,
              toggle_page_numbering_mode: :page_numbering_mode_value,
              toggle_page_numbers: :page_numbers_value,
              toggle_highlight_quotes: :highlight_quotes_value,
              toggle_kitty_images: :kitty_images_value,
            }.freeze

            private

            def display_value_for(action)
              static_value_for(action) ||
                preference_value_for(action) ||
                wipe_cache_toggle_value(action) ||
                default_display_value
            end

            def bool_value(raw, default_truthy, true_text:, false_text:)
              enabled = raw.nil? ? default_truthy : raw == true
              [enabled ? true_text : false_text,
               enabled ? self.class::COLOR_TEXT_SUCCESS : self.class::COLOR_TEXT_WARNING]
            end

            def humanize_symbol(value)
              value.to_s.split('_').map(&:capitalize).join(' ')
            end

            def humanize_theme(theme_id)
              humanize_symbol(theme_id)
            end

            def static_value_for(action)
              case action
              when :back_to_menu
                ['Return', self.class::COLOR_TEXT_DIM]
              when :open_dictionary_settings
                ['Open', self.class::COLOR_TEXT_DIM]
              when :wipe_cache
                ['Run', self.class::COLOR_TEXT_WARNING]
              end
            end

            def preference_value_for(action)
              helper = PREFERENCE_VALUE_HELPERS[action]
              helper && send(helper)
            end

            def accent_value(text)
              [text, self.class::COLOR_TEXT_ACCENT]
            end

            def default_display_value
              ['—', self.class::COLOR_TEXT_DIM]
            end

            def wipe_cache_toggle_value(action)
              return nil unless SettingsScreenComponent::WIPE_CACHE_TOGGLE_ACTIONS.key?(action)

              armed = wipe_cache_checked?(SettingsScreenComponent::WIPE_CACHE_TOGGLE_ACTIONS.fetch(action))
              [armed ? 'Armed' : 'Off', armed ? self.class::COLOR_TEXT_WARNING : self.class::COLOR_TEXT_DIM]
            end

            def current_theme_id
              Shoko::Shared::ThemePolicy.normalize(config_reader&.theme) || Shoko::Shared::ThemePolicy.default_id
            end

            def current_view_mode
              config_reader&.view_mode || :single
            end

            def current_line_spacing
              config_reader&.line_spacing || :normal
            end

            def current_download_source
              Shoko::Shared::DownloadSourcePolicy.normalize(config_reader&.download_source) ||
                Shoko::Shared::DownloadSourcePolicy.default_id
            end

            def current_page_numbering_mode
              config_reader&.page_numbering_mode || :dynamic
            end

            def view_mode_value
              accent_value(humanize_symbol(current_view_mode))
            end

            def line_spacing_value
              accent_value(humanize_symbol(current_line_spacing))
            end

            def download_source_value
              accent_value(Shoko::Shared::DownloadSourcePolicy.label_for(current_download_source))
            end

            def theme_value
              accent_value(humanize_theme(current_theme_id))
            end

            def page_numbering_mode_value
              accent_value(humanize_symbol(current_page_numbering_mode))
            end

            def page_numbers_value
              bool_value(config_reader&.show_page_numbers, true, true_text: 'Enabled', false_text: 'Disabled')
            end

            def highlight_quotes_value
              bool_value(config_reader&.highlight_quotes, true, true_text: 'On', false_text: 'Off')
            end

            def kitty_images_value
              bool_value(config_reader&.kitty_images, false, true_text: 'Enabled', false_text: 'Disabled')
            end
          end
        end
      end
    end
  end
end
