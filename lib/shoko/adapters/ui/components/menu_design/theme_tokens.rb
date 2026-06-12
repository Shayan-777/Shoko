# frozen_string_literal: true

require_relative '../../constants/ui_constants'
require 'shoko/shared/terminal/ansi'
require 'shoko/shared/terminal/text_metrics'
require_relative 'icon_set'

module Shoko
  module Adapters
    module Ui
      module Components
        module MenuDesign
          # Token facade for consistent menu palette and selection styles.
          class ThemeTokens
            include Shoko::Adapters::Ui::Constants::Ui

            def reset = Shoko::Shared::Terminal::Ansi::RESET
            def primary = COLOR_TEXT_PRIMARY
            def accent = COLOR_TEXT_ACCENT
            def dim = MENU_MUTED_FG
            def success = COLOR_TEXT_SUCCESS
            def warning = COLOR_TEXT_WARNING
            def error = COLOR_TEXT_ERROR
            def divider = MENU_DIVIDER_FG
            def heading = "#{Shoko::Shared::Terminal::Ansi::BOLD}#{MENU_TITLE_FG}"
            def panel_heading = "#{Shoko::Shared::Terminal::Ansi::BOLD}#{primary}"
            def header_bg = MENU_HEADER_BG
            def selection_bg = MENU_SELECTION_BG
            def selection_fg = MENU_SELECTION_TEXT

            def brand_badge
              "#{Shoko::Shared::Terminal::Ansi::BOLD}#{accent}SHOKO#{reset}"
            end

            def cursor_glyph
              IconSet.ascii_icons? ? '|' : '▏'
            end

            def style_selected(text)
              "#{selection_bg}#{selection_fg}#{selection_pointer}#{normalize_text(text)}#{reset}"
            end

            def style_unselected(text)
              "#{primary}#{' ' * selection_slot_width}#{normalize_text(text)}#{reset}"
            end

            def selection_pointer
              IconSet.selection_pointer
            end

            def selection_slot_width
              Shoko::Shared::Terminal::TextMetrics.visible_length(selection_pointer)
            end

            private

            def normalize_text(text)
              value = text.to_s
              return value if value.encoding == Encoding::UTF_8 && value.valid_encoding?

              value.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
            rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError, Encoding::CompatibilityError
              value
                .dup
                .force_encoding(Encoding::BINARY)
                .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
            end
          end
        end
      end
    end
  end
end
