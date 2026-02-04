# frozen_string_literal: true

require_relative '../../terminal/terminal'

module Shoko
  module Adapters::Output::Ui
    module Constants
      # Centralized UI color and style definitions
      module UI
        # Dimensions
        MIN_WIDTH = 60
        MIN_HEIGHT = 20

        # Base Colors
        COLOR_TEXT_PRIMARY = Terminal::ANSI::DEFAULT_FG
        COLOR_TEXT_SECONDARY = "#{Terminal::ANSI::DEFAULT_FG}#{Terminal::ANSI::DIM}".freeze
        COLOR_TEXT_DIM = "#{Terminal::ANSI::DEFAULT_FG}#{Terminal::ANSI::DIM}".freeze
        COLOR_TEXT_ACCENT = Terminal::ANSI::BRIGHT_CYAN
        COLOR_TEXT_SUCCESS = Terminal::ANSI::GREEN
        COLOR_TEXT_WARNING = Terminal::ANSI::YELLOW
        COLOR_TEXT_ERROR = Terminal::ANSI::RED

        # Backgrounds
        BG_PRIMARY = Terminal::ANSI::BG_DARK
        BG_ACCENT = Terminal::ANSI::BG_BRIGHT_YELLOW

        # Borders & Dividers
        BORDER_PRIMARY = Terminal::ANSI::GRAY
        BORDER_ACCENT = Terminal::ANSI::BRIGHT_CYAN

        # Selections & Highlights
        SELECTION_POINTER = '▸ '
        SELECTION_FG = Terminal::ANSI::BLACK
        SELECTION_POINTER_COLOR = Terminal::ANSI::BRIGHT_GREEN
        SELECTION_HIGHLIGHT = Terminal::ANSI::BRIGHT_WHITE

        # Overlay/Highlight backgrounds
        HIGHLIGHT_BG_LIGHT = "\e[48;2;230;230;234m"
        HIGHLIGHT_BG_DARK = Terminal::ANSI::BG_GREY
        HIGHLIGHT_BG_ACTIVE = HIGHLIGHT_BG_DARK
        HIGHLIGHT_BG_SAVED = HIGHLIGHT_BG_DARK

        # Popup menu colors
        POPUP_BG_DEFAULT = Terminal::ANSI::BG_SLATE
        POPUP_BG_SELECTED = Terminal::ANSI::BG_SOFT_GREEN
        POPUP_FG_DEFAULT = COLOR_TEXT_PRIMARY
        POPUP_FG_SELECTED = Terminal::ANSI::BLACK

        # Tooltip menu colors
        TOOLTIP_BG_DEFAULT = POPUP_BG_DEFAULT
        TOOLTIP_BG_SELECTED = "\e[48;2;70;104;114m" # Muted blue-gray (blend of slate + #4fd2fd)
        TOOLTIP_FG_DEFAULT = COLOR_TEXT_PRIMARY
        TOOLTIP_FG_SELECTED = COLOR_TEXT_PRIMARY

        # Annotation editor overlay colors
        ANNOTATION_PANEL_BG_LIGHT = "\e[48;2;230;230;234m"
        ANNOTATION_PANEL_BG_DARK = "\e[48;2;88;88;88m"
        ANNOTATION_HEADER_FG_LIGHT = Terminal::ANSI::DEFAULT_FG
        ANNOTATION_HEADER_FG_DARK = "\e[38;2;255;135;135m"
        ANNOTATION_PANEL_BG = ANNOTATION_PANEL_BG_DARK
        ANNOTATION_HEADER_FG = ANNOTATION_HEADER_FG_DARK

        # Toast notification colors
        TOAST_ACCENT = "\e[38;2;135;255;135m"
        TOAST_FG = Terminal::ANSI::DEFAULT_FG

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

        SIDEBAR_BG = Terminal::ANSI::BG_DARK
        SIDEBAR_SELECTION_BG = Terminal::ANSI::BG_BLUE
        SIDEBAR_SELECTION_FG = Terminal::ANSI::BRIGHT_WHITE

        BUTTON_BG_ACTIVE = Terminal::ANSI::BG_BRIGHT_GREEN
        BUTTON_FG_ACTIVE = Terminal::ANSI::BLACK
        BUTTON_BG_INACTIVE = Terminal::ANSI::BG_GREY
        BUTTON_FG_INACTIVE = Terminal::ANSI::WHITE

        def self.apply_color_mode(mode)
          light = mode.to_sym == :light
          set_const(:HIGHLIGHT_BG_ACTIVE, light ? HIGHLIGHT_BG_LIGHT : HIGHLIGHT_BG_DARK)
          set_const(:HIGHLIGHT_BG_SAVED, light ? HIGHLIGHT_BG_LIGHT : HIGHLIGHT_BG_DARK)
          set_const(:ANNOTATION_PANEL_BG, light ? ANNOTATION_PANEL_BG_LIGHT : ANNOTATION_PANEL_BG_DARK)
          set_const(:ANNOTATION_HEADER_FG, light ? ANNOTATION_HEADER_FG_LIGHT : ANNOTATION_HEADER_FG_DARK)
        end

        def self.set_const(name, value)
          remove_const(name) if const_defined?(name)
          const_set(name, value)
        end
      end
    end
  end
end
