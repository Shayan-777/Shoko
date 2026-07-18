# frozen_string_literal: true

require_relative 'constants/themes'
require_relative 'constants/ui'
require_relative 'components/render_style'
require_relative '../../shared/theme_policy'

module Shoko
  module Adapters
    module Ui
      # Canonical runtime theme context used across reader/menu/overlay surfaces.
      class ThemeContext
        Snapshot = Data.define(:theme_id, :color_mode, :palette, :ui_tokens)

        class << self
          def resolve(theme_id:, fallback_color_mode: :dark)
            canonical_theme = Shoko::Shared::ThemePolicy.normalize(theme_id) || Shoko::Shared::ThemePolicy.default_id
            color_mode = Constants::Themes.color_mode_for(canonical_theme, fallback: fallback_color_mode)
            palette = Constants::Themes.palette_for(canonical_theme)
            ui_tokens = token_snapshot(color_mode)
            Snapshot.new(theme_id: canonical_theme, color_mode: color_mode, palette: palette, ui_tokens: ui_tokens)
          end

          def from_reader(config_reader:, fallback_color_mode: :dark)
            resolve(theme_id: config_reader&.theme, fallback_color_mode: fallback_color_mode)
          end

          def apply!(theme_id:, fallback_color_mode: :dark)
            context = resolve(theme_id: theme_id, fallback_color_mode: fallback_color_mode)
            Constants::Ui.apply_color_mode(context.color_mode)
            Components::RenderStyle.configure(context.palette)
            context
          end

          private

          # The menu owns its fixed slate palette (StatusBar::Palette), so the
          # theme snapshot only carries the reader-side mode-dependent tokens.
          def token_snapshot(color_mode)
            color_mode == :light ? light_mode_tokens : dark_mode_tokens
          end

          def light_mode_tokens
            {
              highlight_bg: Constants::Ui::HIGHLIGHT_BG_LIGHT,
              annotation_panel_bg: Constants::Ui::ANNOTATION_PANEL_BG_LIGHT,
            }.freeze
          end

          def dark_mode_tokens
            {
              highlight_bg: Constants::Ui::HIGHLIGHT_BG_DARK,
              annotation_panel_bg: Constants::Ui::ANNOTATION_PANEL_BG_DARK,
            }.freeze
          end
        end
      end
    end
  end
end
