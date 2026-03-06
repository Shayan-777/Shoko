# frozen_string_literal: true

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
            standard: DEFAULT_PALETTE,
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

          LEGACY_THEME_ALIASES = {
            dark: :default,
            light: :gray,
          }.freeze

          THEME_COLOR_MODES = {
            default: :dark,
            standard: :dark,
            gray: :light,
            sepia: :light,
            grass: :dark,
            cherry: :dark,
            sky: :dark,
            solarized: :dark,
            gruvbox: :dark,
            nord: :dark,
          }.freeze

          USER_THEMES = THEMES.keys.reject { |key| key == :standard }.freeze

          module_function

          def available_themes(include_aliases: false)
            include_aliases ? THEMES.keys : USER_THEMES
          end

          def canonical_theme(theme)
            key = normalize_theme_key(theme)
            return nil unless key

            canonical = LEGACY_THEME_ALIASES.fetch(key, key)
            return canonical if THEMES.key?(canonical)

            nil
          end

          def normalize_theme(theme, fallback: :default)
            canonical_theme(theme) || canonical_theme(fallback) || :default
          end

          def valid_theme?(theme)
            !canonical_theme(theme).nil?
          end

          def color_mode_for(theme, fallback: :dark)
            canonical = normalize_theme(theme, fallback: :default)
            fallback_mode = normalize_color_mode(fallback)
            THEME_COLOR_MODES.fetch(canonical, fallback_mode)
          end

          def palette_for(theme)
            canonical = normalize_theme(theme, fallback: :default)
            THEMES.fetch(canonical, DEFAULT_PALETTE)
          end

          def normalize_color_mode(mode)
            mode.to_s.strip.downcase == 'light' ? :light : :dark
          end

          def normalize_theme_key(theme)
            return nil if theme.nil?

            key = theme.is_a?(Symbol) ? theme : theme.to_s.strip.downcase.to_sym
            return nil if key == :''

            key
          end
          private_class_method :normalize_theme_key
        end
      end
    end
  end
end
