# frozen_string_literal: true

require_relative '../../terminal/terminal.rb'

module Shoko
  module Adapters::Output::Ui
    module Constants
      # Theme palettes used by the terminal render style system.
      module Themes
        DEFAULT_PALETTE = {
          primary: Terminal::ANSI::DEFAULT_FG,
          accent: Terminal::ANSI::BRIGHT_CYAN,
          heading: Terminal::ANSI::BRIGHT_GREEN,
          dim: "#{Terminal::ANSI::DEFAULT_FG}#{Terminal::ANSI::DIM}",
          quote: "#{Terminal::ANSI::DEFAULT_FG}#{Terminal::ANSI::DIM}",
          code: Terminal::ANSI::YELLOW,
          separator: "#{Terminal::ANSI::DEFAULT_FG}#{Terminal::ANSI::DIM}",
          prefix: "#{Terminal::ANSI::DEFAULT_FG}#{Terminal::ANSI::DIM}",
        }.freeze

        THEMES = {
          default: DEFAULT_PALETTE,
          standard: DEFAULT_PALETTE,
          gray: DEFAULT_PALETTE.merge(
            primary: Terminal::ANSI::LIGHT_GREY,
            accent: Terminal::ANSI::BRIGHT_WHITE,
            quote: Terminal::ANSI::GRAY
          ).freeze,
          sepia: DEFAULT_PALETTE.merge(
            primary: Terminal::ANSI::YELLOW,
            accent: Terminal::ANSI::BRIGHT_YELLOW,
            dim: Terminal::ANSI::DIM,
            quote: Terminal::ANSI::BRIGHT_YELLOW
          ).freeze,
          grass: DEFAULT_PALETTE.merge(
            primary: Terminal::ANSI::GREEN,
            accent: Terminal::ANSI::BRIGHT_GREEN,
            quote: Terminal::ANSI::GREEN
          ).freeze,
          cherry: DEFAULT_PALETTE.merge(
            primary: Terminal::ANSI::RED,
            accent: Terminal::ANSI::BRIGHT_RED,
            quote: Terminal::ANSI::BRIGHT_RED
          ).freeze,
          sky: DEFAULT_PALETTE.merge(
            primary: Terminal::ANSI::BLUE,
            accent: Terminal::ANSI::BRIGHT_BLUE,
            quote: Terminal::ANSI::BRIGHT_BLUE
          ).freeze,
          solarized: DEFAULT_PALETTE.merge(
            primary: Terminal::ANSI::CYAN,
            accent: Terminal::ANSI::BRIGHT_CYAN,
            quote: Terminal::ANSI::BRIGHT_CYAN
          ).freeze,
          gruvbox: DEFAULT_PALETTE.merge(
            primary: Terminal::ANSI::YELLOW,
            accent: Terminal::ANSI::BRIGHT_GREEN,
            quote: Terminal::ANSI::BRIGHT_YELLOW
          ).freeze,
          nord: DEFAULT_PALETTE.merge(
            primary: Terminal::ANSI::BRIGHT_BLUE,
            accent: Terminal::ANSI::BRIGHT_CYAN,
            quote: Terminal::ANSI::BRIGHT_CYAN
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
