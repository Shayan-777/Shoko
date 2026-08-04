# frozen_string_literal: true

require 'shoko/core/policies/theme_policy'
require 'shoko/shared/terminal/ansi'
require 'shoko/shared/terminal/color_depth'

module Shoko
  module Adapters
    module Ui
      module Constants
        # Theme palettes used by the terminal render style system.
        #
        # Each theme has two palettes: a 16-color ANSI approximation (works
        # everywhere) and a truecolor palette with the theme's real colors,
        # chosen automatically when the terminal advertises 24-bit support.
        module Themes
          def self.fg(hex)
            r, g, b = hex.delete_prefix('#').scan(/../).map { |pair| pair.to_i(16) }
            "\e[38;2;#{r};#{g};#{b}m"
          end

          def self.bg(hex)
            r, g, b = hex.delete_prefix('#').scan(/../).map { |pair| pair.to_i(16) }
            "\e[48;2;#{r};#{g};#{b}m"
          end

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

          # Truecolor palettes: the colors these themes actually mean. The
          # default theme keeps the terminal's own foreground and only tints
          # accents, so it stays honest on light and dark terminals alike.
          TRUECOLOR_THEMES = {
            default: DEFAULT_PALETTE.merge(
              accent: fg('#56b6c2'),
              link: fg('#61afef'),
              heading: fg('#98c379'),
              code: fg('#e5c07b')
            ).freeze,
            gray: DEFAULT_PALETTE.merge(
              primary: fg('#2e2e2e'),
              accent: fg('#111111'),
              heading: fg('#1a1a1a'),
              link: fg('#2960a5'),
              quote: fg('#5a5a5a'),
              code: fg('#7a4a12')
            ).freeze,
            sepia: DEFAULT_PALETTE.merge(
              primary: fg('#5b4636'),
              accent: fg('#8a5a2c'),
              heading: fg('#6d4c2f'),
              link: fg('#59702e'),
              quote: fg('#7d6a55'),
              dim: fg('#8f7c66'),
              separator: fg('#a08b73'),
              prefix: fg('#8f7c66'),
              code: fg('#75513a')
            ).freeze,
            grass: DEFAULT_PALETTE.merge(
              primary: fg('#9ec49a'),
              accent: fg('#b8e6b0'),
              heading: fg('#c6e2b8'),
              link: fg('#7dc4a8'),
              quote: fg('#7ba377'),
              code: fg('#d3c66b')
            ).freeze,
            cherry: DEFAULT_PALETTE.merge(
              primary: fg('#d8a0a8'),
              accent: fg('#e06c75'),
              heading: fg('#ea8f97'),
              link: fg('#c678dd'),
              quote: fg('#b07f86'),
              code: fg('#d19a66')
            ).freeze,
            sky: DEFAULT_PALETTE.merge(
              primary: fg('#a3c5e8'),
              accent: fg('#61afef'),
              heading: fg('#7fbcf2'),
              link: fg('#56b6c2'),
              quote: fg('#82a1c1'),
              code: fg('#c8ae7d')
            ).freeze,
            solarized: DEFAULT_PALETTE.merge(
              primary: fg('#839496'),
              accent: fg('#2aa198'),
              heading: fg('#b58900'),
              link: fg('#268bd2'),
              quote: fg('#657b83'),
              code: fg('#cb4b16'),
              code_bg: bg('#073642')
            ).freeze,
            gruvbox: DEFAULT_PALETTE.merge(
              primary: fg('#ebdbb2'),
              accent: fg('#b8bb26'),
              heading: fg('#fabd2f'),
              link: fg('#83a598'),
              quote: fg('#bdae93'),
              code: fg('#fe8019'),
              code_bg: bg('#3c3836')
            ).freeze,
            nord: DEFAULT_PALETTE.merge(
              primary: fg('#d8dee9'),
              accent: fg('#88c0d0'),
              heading: fg('#ebcb8b'),
              link: fg('#81a1c1'),
              quote: fg('#aab6cc'),
              code: fg('#d08770'),
              code_bg: bg('#3b4252')
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
            themes = Shoko::Core::Policies::ThemePolicy.canonical_ids
            return themes unless include_aliases

            (themes + Shoko::Core::Policies::ThemePolicy.aliases.keys).uniq
          end

          def color_mode_for(theme, fallback: :dark)
            canonical = Shoko::Core::Policies::ThemePolicy.normalize(theme) || Shoko::Core::Policies::ThemePolicy.default_id
            fallback_mode = normalize_color_mode(fallback)
            THEME_COLOR_MODES.fetch(canonical, fallback_mode)
          end

          def palette_for(theme, truecolor: Shoko::Shared::Terminal::ColorDepth.truecolor?)
            canonical = Shoko::Core::Policies::ThemePolicy.normalize(theme) || Shoko::Core::Policies::ThemePolicy.default_id
            return TRUECOLOR_THEMES.fetch(canonical, DEFAULT_PALETTE) if truecolor

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
