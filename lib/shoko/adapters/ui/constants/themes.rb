# frozen_string_literal: true

require_relative '../../../shared/theme_policy'
require_relative '../../../shared/terminal/ansi'

module Shoko
  module Adapters
    module Ui
      module Constants
        # Theme palettes used by the terminal render style system.
        module Themes
          DEFAULT_PALETTE = {
            primary: Shoko::Shared::Terminal::Ansi::DEFAULT_FG,
            accent: Shoko::Shared::Terminal::Ansi::BRIGHT_CYAN,
            link: Shoko::Shared::Terminal::Ansi::BRIGHT_BLUE,
            heading: Shoko::Shared::Terminal::Ansi::BRIGHT_GREEN,
            dim: "#{Shoko::Shared::Terminal::Ansi::DEFAULT_FG}#{Shoko::Shared::Terminal::Ansi::DIM}",
            quote: "#{Shoko::Shared::Terminal::Ansi::DEFAULT_FG}#{Shoko::Shared::Terminal::Ansi::DIM}",
            code: Shoko::Shared::Terminal::Ansi::YELLOW,
            separator: "#{Shoko::Shared::Terminal::Ansi::DEFAULT_FG}#{Shoko::Shared::Terminal::Ansi::DIM}",
            prefix: "#{Shoko::Shared::Terminal::Ansi::DEFAULT_FG}#{Shoko::Shared::Terminal::Ansi::DIM}",
          }.freeze

          THEMES = {
            default: DEFAULT_PALETTE,
            gray: DEFAULT_PALETTE.merge(
              primary: Shoko::Shared::Terminal::Ansi::BLACK,
              accent: Shoko::Shared::Terminal::Ansi::BRIGHT_WHITE,
              quote: Shoko::Shared::Terminal::Ansi::GRAY
            ).freeze,
            sepia: DEFAULT_PALETTE.merge(
              primary: Shoko::Shared::Terminal::Ansi::YELLOW,
              accent: Shoko::Shared::Terminal::Ansi::BRIGHT_YELLOW,
              dim: Shoko::Shared::Terminal::Ansi::DIM,
              quote: Shoko::Shared::Terminal::Ansi::BRIGHT_YELLOW
            ).freeze,
            grass: DEFAULT_PALETTE.merge(
              primary: Shoko::Shared::Terminal::Ansi::GREEN,
              accent: Shoko::Shared::Terminal::Ansi::BRIGHT_GREEN,
              quote: Shoko::Shared::Terminal::Ansi::GREEN
            ).freeze,
            cherry: DEFAULT_PALETTE.merge(
              primary: Shoko::Shared::Terminal::Ansi::RED,
              accent: Shoko::Shared::Terminal::Ansi::BRIGHT_RED,
              quote: Shoko::Shared::Terminal::Ansi::BRIGHT_RED
            ).freeze,
            sky: DEFAULT_PALETTE.merge(
              primary: Shoko::Shared::Terminal::Ansi::BLUE,
              accent: Shoko::Shared::Terminal::Ansi::BRIGHT_BLUE,
              quote: Shoko::Shared::Terminal::Ansi::BRIGHT_BLUE
            ).freeze,
            solarized: DEFAULT_PALETTE.merge(
              primary: Shoko::Shared::Terminal::Ansi::CYAN,
              accent: Shoko::Shared::Terminal::Ansi::BRIGHT_CYAN,
              quote: Shoko::Shared::Terminal::Ansi::BRIGHT_CYAN
            ).freeze,
            gruvbox: DEFAULT_PALETTE.merge(
              primary: Shoko::Shared::Terminal::Ansi::YELLOW,
              accent: Shoko::Shared::Terminal::Ansi::BRIGHT_GREEN,
              quote: Shoko::Shared::Terminal::Ansi::BRIGHT_YELLOW
            ).freeze,
            nord: DEFAULT_PALETTE.merge(
              primary: Shoko::Shared::Terminal::Ansi::BRIGHT_BLUE,
              accent: Shoko::Shared::Terminal::Ansi::BRIGHT_CYAN,
              quote: Shoko::Shared::Terminal::Ansi::BRIGHT_CYAN
            ).freeze,
          }.freeze

          THEME_COLOR_MODES = {
            default: :dark,
            gray: :light,
            sepia: :light,
            grass: :dark,
            cherry: :dark,
            sky: :dark,
            solarized: :dark,
            gruvbox: :dark,
            nord: :dark,
          }.freeze

          module_function

          def available_themes(include_aliases: false)
            themes = Shoko::Shared::ThemePolicy.canonical_ids
            return themes unless include_aliases

            (themes + Shoko::Shared::ThemePolicy.aliases.keys).uniq
          end

          def color_mode_for(theme, fallback: :dark)
            canonical = Shoko::Shared::ThemePolicy.normalize(theme) || Shoko::Shared::ThemePolicy.default_id
            fallback_mode = normalize_color_mode(fallback)
            THEME_COLOR_MODES.fetch(canonical, fallback_mode)
          end

          def palette_for(theme)
            canonical = Shoko::Shared::ThemePolicy.normalize(theme) || Shoko::Shared::ThemePolicy.default_id
            THEMES.fetch(canonical, DEFAULT_PALETTE)
          end

          def normalize_color_mode(mode)
            mode.to_s.strip.downcase == 'light' ? :light : :dark
          end
        end
      end
    end
  end
end
