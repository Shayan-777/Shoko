# frozen_string_literal: true

require 'shoko/shared/terminal/ansi'
require 'shoko/adapters/ui/ui_constraints'

module Shoko
  module Adapters
    module Ui
      module Constants
        # Centralized UI color and style definitions
        module Ui
          # Dimensions
          MIN_WIDTH = Shoko::Adapters::Ui::UiConstraints::MIN_TERMINAL_WIDTH
          MIN_HEIGHT = Shoko::Adapters::Ui::UiConstraints::MIN_TERMINAL_HEIGHT

          # Base Colors
          COLOR_TEXT_PRIMARY = Shoko::Shared::Terminal::Ansi::DEFAULT_FG
          COLOR_TEXT_SECONDARY = "#{Shoko::Shared::Terminal::Ansi::DEFAULT_FG}#{Shoko::Shared::Terminal::Ansi::DIM}".freeze
          COLOR_TEXT_DIM = "#{Shoko::Shared::Terminal::Ansi::DEFAULT_FG}#{Shoko::Shared::Terminal::Ansi::DIM}".freeze
          COLOR_TEXT_ACCENT = Shoko::Shared::Terminal::Ansi::BRIGHT_CYAN
          COLOR_TEXT_SUCCESS = Shoko::Shared::Terminal::Ansi::GREEN
          COLOR_TEXT_WARNING = Shoko::Shared::Terminal::Ansi::YELLOW
          COLOR_TEXT_ERROR = Shoko::Shared::Terminal::Ansi::RED

          # Backgrounds
          BG_PRIMARY = Shoko::Shared::Terminal::Ansi::BG_DARK
          BG_ACCENT = Shoko::Shared::Terminal::Ansi::BG_BRIGHT_YELLOW

          # Borders & Dividers
          BORDER_PRIMARY = Shoko::Shared::Terminal::Ansi::GRAY
          BORDER_ACCENT = Shoko::Shared::Terminal::Ansi::BRIGHT_CYAN

          # Selections & Highlights
          SELECTION_POINTER = '▸ '
          SELECTION_FG = Shoko::Shared::Terminal::Ansi::BLACK
          SELECTION_POINTER_COLOR = Shoko::Shared::Terminal::Ansi::BRIGHT_GREEN
          SELECTION_HIGHLIGHT = Shoko::Shared::Terminal::Ansi::BRIGHT_WHITE

          # Overlay/Highlight backgrounds
          HIGHLIGHT_BG_LIGHT = "\e[48;2;230;230;234m"
          HIGHLIGHT_BG_DARK = "\e[48;2;52;56;70m"
          HIGHLIGHT_BG_ACTIVE = HIGHLIGHT_BG_DARK
          HIGHLIGHT_BG_SAVED = HIGHLIGHT_BG_DARK
          # Search-result landing highlight: an orange background pulse on the
          # matched text (the same amber the search results use, applied as the
          # background rather than the glyph color), with dark text for contrast.
          SEARCH_HIGHLIGHT_BG_LIGHT = "\e[48;2;245;200;120m"
          SEARCH_HIGHLIGHT_BG_DARK = "\e[48;2;245;200;120m"
          SEARCH_HIGHLIGHT_BG = SEARCH_HIGHLIGHT_BG_DARK
          SEARCH_HIGHLIGHT_FG_LIGHT = "\e[38;2;28;30;40m#{Shoko::Shared::Terminal::Ansi::BOLD}".freeze
          SEARCH_HIGHLIGHT_FG_DARK = "\e[38;2;28;30;40m#{Shoko::Shared::Terminal::Ansi::BOLD}".freeze
          SEARCH_HIGHLIGHT_FG = SEARCH_HIGHLIGHT_FG_DARK

          # Popup menu colors
          POPUP_BG_DEFAULT = Shoko::Shared::Terminal::Ansi::BG_SLATE
          POPUP_BG_SELECTED = Shoko::Shared::Terminal::Ansi::BG_SOFT_GREEN
          POPUP_FG_DEFAULT = COLOR_TEXT_PRIMARY
          POPUP_FG_SELECTED = Shoko::Shared::Terminal::Ansi::BLACK

          # Tooltip menu colors
          # Keep palette close to LazyVim-style popup menus:
          # muted slate base, subtle gray-blue selection, low-saturation foreground.
          TOOLTIP_GLASS_BG_DEFAULT = "\e[48;2;30;30;46m"
          TOOLTIP_GLASS_BG_SELECTED = "\e[48;2;69;71;90m"
          TOOLTIP_GLASS_FG_DEFAULT = "\e[38;2;56;60;78m#{Shoko::Shared::Terminal::Ansi::DIM}".freeze
          TOOLTIP_GLASS_FG_SELECTED = "\e[38;2;92;98;122m#{Shoko::Shared::Terminal::Ansi::DIM}".freeze

          TOOLTIP_BG_DEFAULT = TOOLTIP_GLASS_BG_DEFAULT
          TOOLTIP_BG_SELECTED = TOOLTIP_GLASS_BG_SELECTED
          TOOLTIP_FG_DEFAULT = "\e[38;2;205;214;244m"
          TOOLTIP_FG_SELECTED = "\e[38;2;220;227;252m"

          # Annotation editor overlay colors
          ANNOTATION_PANEL_BG_LIGHT = "\e[48;2;230;230;234m"
          ANNOTATION_PANEL_BG_DARK = "\e[48;2;88;88;88m"
          ANNOTATION_HEADER_FG_LIGHT = Shoko::Shared::Terminal::Ansi::DEFAULT_FG
          ANNOTATION_HEADER_FG_DARK = "\e[38;2;255;135;135m"
          ANNOTATION_PANEL_BG = ANNOTATION_PANEL_BG_DARK
          ANNOTATION_HEADER_FG = ANNOTATION_HEADER_FG_DARK

          # Toast notification colors
          TOAST_ACCENT = "\e[38;2;135;255;135m"
          TOAST_FG = Shoko::Shared::Terminal::Ansi::DEFAULT_FG

          # Icons
          ICON_BOOK = '󰂺'
          ICON_RECENT = '󰁯'
          ICON_ANNOTATION = '󰠮'
          ICON_SETTINGS = ''
          ICON_QUIT = '󰿅'
          ICON_OPEN = '󰷏'
          ICON_TOC = '📖'
          ICON_BOOKMARK = '🔖'
          ICON_HELP = '❓'
          ICON_SEARCH = ''
          ICON_REFRESH = ''

          # Reader-side tokens that flip with the theme's light/dark mode.
          # (The menu keeps its own fixed slate palette — StatusBar::Palette —
          # the way editor status bars stay one color across themes.)
          COLOR_MODE_PAIRS = [
            [:HIGHLIGHT_BG_ACTIVE, HIGHLIGHT_BG_LIGHT, HIGHLIGHT_BG_DARK],
            [:HIGHLIGHT_BG_SAVED, HIGHLIGHT_BG_LIGHT, HIGHLIGHT_BG_DARK],
            [:SEARCH_HIGHLIGHT_BG, SEARCH_HIGHLIGHT_BG_LIGHT, SEARCH_HIGHLIGHT_BG_DARK],
            [:SEARCH_HIGHLIGHT_FG, SEARCH_HIGHLIGHT_FG_LIGHT, SEARCH_HIGHLIGHT_FG_DARK],
            [:ANNOTATION_PANEL_BG, ANNOTATION_PANEL_BG_LIGHT, ANNOTATION_PANEL_BG_DARK],
            [:ANNOTATION_HEADER_FG, ANNOTATION_HEADER_FG_LIGHT, ANNOTATION_HEADER_FG_DARK],
          ].freeze

          def self.apply_color_mode(mode)
            light = mode.to_sym == :light
            COLOR_MODE_PAIRS.each do |name, light_value, dark_value|
              set_const(name, light ? light_value : dark_value)
            end
          end

          def self.set_const(name, value)
            remove_const(name) if const_defined?(name)
            const_set(name, value)
          end
        end
      end
    end
  end
end
