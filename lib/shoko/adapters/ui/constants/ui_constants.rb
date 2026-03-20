# frozen_string_literal: true

require_relative '../../../shared/terminal/ansi'
require_relative '../../../shared/ui_constraints'

module Shoko
  module Adapters
    module Ui
      module Constants
        # Centralized UI color and style definitions
        module Ui
          # Dimensions
          MIN_WIDTH = Shoko::Shared::UiConstraints::MIN_TERMINAL_WIDTH
          MIN_HEIGHT = Shoko::Shared::UiConstraints::MIN_TERMINAL_HEIGHT

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
          SEARCH_HIGHLIGHT_BG_LIGHT = "\e[48;2;191;229;240m"
          SEARCH_HIGHLIGHT_BG_DARK = "\e[48;2;34;101;128m"
          SEARCH_HIGHLIGHT_BG = SEARCH_HIGHLIGHT_BG_DARK
          SEARCH_HIGHLIGHT_FG_LIGHT = "\e[38;2;12;54;71m#{Shoko::Shared::Terminal::Ansi::BOLD}".freeze
          SEARCH_HIGHLIGHT_FG_DARK = "\e[38;2;236;248;255m#{Shoko::Shared::Terminal::Ansi::BOLD}".freeze
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

          SIDEBAR_BG = Shoko::Shared::Terminal::Ansi::BG_DARK
          SIDEBAR_SELECTION_BG = Shoko::Shared::Terminal::Ansi::BG_BLUE
          SIDEBAR_SELECTION_FG = Shoko::Shared::Terminal::Ansi::BRIGHT_WHITE

          BUTTON_BG_ACTIVE = Shoko::Shared::Terminal::Ansi::BG_BRIGHT_GREEN
          BUTTON_FG_ACTIVE = Shoko::Shared::Terminal::Ansi::BLACK
          BUTTON_BG_INACTIVE = Shoko::Shared::Terminal::Ansi::BG_GREY
          BUTTON_FG_INACTIVE = Shoko::Shared::Terminal::Ansi::WHITE

          # Menu-specific slate/cyan editorial tokens.
          MENU_SURFACE_BG_LIGHT = "\e[48;2;242;245;248m"
          MENU_SURFACE_BG_DARK = "\e[48;2;26;32;40m"
          MENU_SURFACE_BG = MENU_SURFACE_BG_DARK

          MENU_TITLE_FG_LIGHT = "\e[38;2;11;79;107m"
          MENU_TITLE_FG_DARK = Shoko::Shared::Terminal::Ansi::BRIGHT_CYAN
          MENU_TITLE_FG = MENU_TITLE_FG_DARK

          MENU_MUTED_FG_LIGHT = "\e[38;2;94;108;124m"
          MENU_MUTED_FG_DARK = COLOR_TEXT_DIM
          MENU_MUTED_FG = MENU_MUTED_FG_DARK

          MENU_DIVIDER_FG_LIGHT = "\e[38;2;138;150;166m"
          MENU_DIVIDER_FG_DARK = Shoko::Shared::Terminal::Ansi::GRAY
          MENU_DIVIDER_FG = MENU_DIVIDER_FG_DARK

          MENU_SELECTION_FG_LIGHT = "\e[38;2;8;101;143m"
          MENU_SELECTION_FG_DARK = COLOR_TEXT_ACCENT
          MENU_SELECTION_FG = MENU_SELECTION_FG_DARK

          MENU_HEADER_BG_LIGHT = "\e[48;2;225;236;244m"
          MENU_HEADER_BG_DARK = "\e[48;2;18;44;58m"
          MENU_HEADER_BG = MENU_HEADER_BG_DARK

          MENU_SELECTION_BG_LIGHT = "\e[48;2;208;232;246m"
          MENU_SELECTION_BG_DARK = "\e[48;2;23;63;83m"
          MENU_SELECTION_BG = MENU_SELECTION_BG_DARK

          MENU_SELECTION_TEXT_LIGHT = "\e[38;2;6;67;95m"
          MENU_SELECTION_TEXT_DARK = "\e[38;2;180;235;255m"
          MENU_SELECTION_TEXT = MENU_SELECTION_TEXT_DARK
          COLOR_MODE_PAIRS = [
            [:HIGHLIGHT_BG_ACTIVE, HIGHLIGHT_BG_LIGHT, HIGHLIGHT_BG_DARK],
            [:HIGHLIGHT_BG_SAVED, HIGHLIGHT_BG_LIGHT, HIGHLIGHT_BG_DARK],
            [:SEARCH_HIGHLIGHT_BG, SEARCH_HIGHLIGHT_BG_LIGHT, SEARCH_HIGHLIGHT_BG_DARK],
            [:SEARCH_HIGHLIGHT_FG, SEARCH_HIGHLIGHT_FG_LIGHT, SEARCH_HIGHLIGHT_FG_DARK],
            [:ANNOTATION_PANEL_BG, ANNOTATION_PANEL_BG_LIGHT, ANNOTATION_PANEL_BG_DARK],
            [:ANNOTATION_HEADER_FG, ANNOTATION_HEADER_FG_LIGHT, ANNOTATION_HEADER_FG_DARK],
            [:MENU_SURFACE_BG, MENU_SURFACE_BG_LIGHT, MENU_SURFACE_BG_DARK],
            [:MENU_TITLE_FG, MENU_TITLE_FG_LIGHT, MENU_TITLE_FG_DARK],
            [:MENU_MUTED_FG, MENU_MUTED_FG_LIGHT, MENU_MUTED_FG_DARK],
            [:MENU_DIVIDER_FG, MENU_DIVIDER_FG_LIGHT, MENU_DIVIDER_FG_DARK],
            [:MENU_SELECTION_FG, MENU_SELECTION_FG_LIGHT, MENU_SELECTION_FG_DARK],
            [:MENU_HEADER_BG, MENU_HEADER_BG_LIGHT, MENU_HEADER_BG_DARK],
            [:MENU_SELECTION_BG, MENU_SELECTION_BG_LIGHT, MENU_SELECTION_BG_DARK],
            [:MENU_SELECTION_TEXT, MENU_SELECTION_TEXT_LIGHT, MENU_SELECTION_TEXT_DARK],
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
