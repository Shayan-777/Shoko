# frozen_string_literal: true

require_relative 'constants/themes'
require_relative 'constants/ui_constants'
require_relative 'components/render_style'

module Shoko
  module Adapters
    module Ui
      # Canonical runtime theme context used across reader/menu/overlay surfaces.
      class ThemeContext
        Snapshot = Data.define(:theme_id, :color_mode, :palette, :ui_tokens)

        class << self
          def resolve(theme_id:, fallback_color_mode: :dark)
            canonical_theme = Constants::Themes.normalize_theme(theme_id)
            color_mode = Constants::Themes.color_mode_for(canonical_theme, fallback: fallback_color_mode)
            palette = Constants::Themes.palette_for(canonical_theme)
            ui_tokens = token_snapshot(color_mode)
            Snapshot.new(theme_id: canonical_theme, color_mode: color_mode, palette: palette, ui_tokens: ui_tokens)
          end

          def from_reader(config_reader:, fallback_color_mode: :dark)
            resolve(
              theme_id: config_reader&.theme,
              fallback_color_mode: fallback_color_mode
            )
          end

          def apply!(theme_id:, fallback_color_mode: :dark)
            context = resolve(theme_id: theme_id, fallback_color_mode: fallback_color_mode)
            Constants::Ui.apply_color_mode(context.color_mode)
            Components::RenderStyle.configure(context.palette)
            context
          end

          private

          def token_snapshot(color_mode)
            color_mode == :light ? light_mode_tokens : dark_mode_tokens
          end

          def light_mode_tokens
            {
              menu_surface_bg: Constants::Ui::MENU_SURFACE_BG_LIGHT,
              menu_title_fg: Constants::Ui::MENU_TITLE_FG_LIGHT,
              menu_muted_fg: Constants::Ui::MENU_MUTED_FG_LIGHT,
              menu_divider_fg: Constants::Ui::MENU_DIVIDER_FG_LIGHT,
              menu_selection_fg: Constants::Ui::MENU_SELECTION_FG_LIGHT,
              menu_header_bg: Constants::Ui::MENU_HEADER_BG_LIGHT,
              menu_selection_bg: Constants::Ui::MENU_SELECTION_BG_LIGHT,
              menu_selection_text: Constants::Ui::MENU_SELECTION_TEXT_LIGHT,
              highlight_bg: Constants::Ui::HIGHLIGHT_BG_LIGHT,
              annotation_panel_bg: Constants::Ui::ANNOTATION_PANEL_BG_LIGHT,
            }.freeze
          end

          def dark_mode_tokens
            {
              menu_surface_bg: Constants::Ui::MENU_SURFACE_BG_DARK,
              menu_title_fg: Constants::Ui::MENU_TITLE_FG_DARK,
              menu_muted_fg: Constants::Ui::MENU_MUTED_FG_DARK,
              menu_divider_fg: Constants::Ui::MENU_DIVIDER_FG_DARK,
              menu_selection_fg: Constants::Ui::MENU_SELECTION_FG_DARK,
              menu_header_bg: Constants::Ui::MENU_HEADER_BG_DARK,
              menu_selection_bg: Constants::Ui::MENU_SELECTION_BG_DARK,
              menu_selection_text: Constants::Ui::MENU_SELECTION_TEXT_DARK,
              highlight_bg: Constants::Ui::HIGHLIGHT_BG_DARK,
              annotation_panel_bg: Constants::Ui::ANNOTATION_PANEL_BG_DARK,
            }.freeze
          end
        end
      end
    end
  end
end
