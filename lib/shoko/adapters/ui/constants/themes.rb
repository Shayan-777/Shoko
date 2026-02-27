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
              primary: Shoko::Shared::Terminal::Ansi::LIGHT_GREY,
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

          module_function

          def palette_for(theme)
            theme_key = theme&.to_sym
            base = DEFAULT_PALETTE
            return base unless theme_key

            THEMES[theme_key] || base
          end
        end
      end
    end
  end
end
