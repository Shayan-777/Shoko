# frozen_string_literal: true

require_relative '../../../constants/ui_constants'
require_relative '../../../../../shared/terminal/ansi'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Palette helpers for the translator screen.
          module TranslatorScreenComponentPaletteSupport
            UI = Adapters::Ui::Constants::Ui
            BOLD = Shoko::Shared::Terminal::Ansi::BOLD
            DIM = Shoko::Shared::Terminal::Ansi::DIM

            SOURCE_PANEL_BG_LIGHT = "\e[48;2;232;239;245m"
            SOURCE_PANEL_BG_DARK = "\e[48;2;20;35;48m"
            TARGET_PANEL_BG_LIGHT = "\e[48;2;232;240;236m"
            TARGET_PANEL_BG_DARK = "\e[48;2;19;40;35m"
            SOURCE_ACCENT_LIGHT = "\e[38;2;18;90;122m"
            SOURCE_ACCENT_DARK = "\e[38;2;129;208;235m"
            TARGET_ACCENT_LIGHT = "\e[38;2;44;112;88m"
            TARGET_ACCENT_DARK = "\e[38;2;161;226;196m"
            SOURCE_CURSOR_BG_LIGHT = "\e[48;2;185;214;228m"
            SOURCE_CURSOR_BG_DARK = "\e[48;2;73;107;126m"
            CURSOR_FG_LIGHT = "\e[38;2;22;40;57m#{BOLD}".freeze
            CURSOR_FG_DARK = "\e[38;2;242;246;255m#{BOLD}".freeze
            DROPDOWN_BG_LIGHT = "\e[48;2;231;236;243m"
            DROPDOWN_BG_DARK = "\e[48;2;31;35;53m"
            DROPDOWN_SELECTED_BG_LIGHT = "\e[48;2;210;220;236m"
            DROPDOWN_SELECTED_BG_DARK = "\e[48;2;67;74;108m"
            DROPDOWN_FG_LIGHT = "\e[38;2;43;50;63m"
            DROPDOWN_FG_DARK = "\e[38;2;211;220;246m"
            DROPDOWN_SELECTED_FG_LIGHT = "\e[38;2;22;40;57m#{BOLD}".freeze
            DROPDOWN_SELECTED_FG_DARK = "\e[38;2;242;246;255m#{BOLD}".freeze
            DROPDOWN_MUTED_FG_LIGHT = "\e[38;2;122;131;149m"
            DROPDOWN_MUTED_FG_DARK = "\e[38;2;125;132;162m"
            PANEL_TEXT_FG_LIGHT = "\e[38;2;40;48;62m"
            PANEL_TEXT_FG_DARK = UI::TOOLTIP_FG_DEFAULT
            PANEL_MUTED_FG_LIGHT = "\e[38;2;108;118;133m"
            PANEL_MUTED_FG_DARK = UI::MENU_MUTED_FG

            private

            def status_left_color
              case translator_status
              when :done
                panel_accent(:target)
              when :error
                UI::COLOR_TEXT_ERROR
              when :loading, :working
                UI::MENU_SELECTION_FG
              when :ready
                panel_accent(:source)
              else
                UI::MENU_MUTED_FG
              end
            end

            def panel_bg(kind)
              return light_mode? ? SOURCE_PANEL_BG_LIGHT : SOURCE_PANEL_BG_DARK if kind == :source

              light_mode? ? TARGET_PANEL_BG_LIGHT : TARGET_PANEL_BG_DARK
            end

            def panel_accent(kind)
              return light_mode? ? SOURCE_ACCENT_LIGHT : SOURCE_ACCENT_DARK if kind == :source

              light_mode? ? TARGET_ACCENT_LIGHT : TARGET_ACCENT_DARK
            end

            def panel_border_color(kind)
              return panel_accent(kind) if panel_active?(kind)

              "#{panel_accent(kind)}#{DIM}"
            end

            def panel_text_fg
              light_mode? ? PANEL_TEXT_FG_LIGHT : PANEL_TEXT_FG_DARK
            end

            def panel_muted_fg
              light_mode? ? PANEL_MUTED_FG_LIGHT : PANEL_MUTED_FG_DARK
            end

            def dropdown_bg
              light_mode? ? DROPDOWN_BG_LIGHT : DROPDOWN_BG_DARK
            end

            def dropdown_selected_bg
              light_mode? ? DROPDOWN_SELECTED_BG_LIGHT : DROPDOWN_SELECTED_BG_DARK
            end

            def dropdown_fg
              light_mode? ? DROPDOWN_FG_LIGHT : DROPDOWN_FG_DARK
            end

            def dropdown_selected_fg
              light_mode? ? DROPDOWN_SELECTED_FG_LIGHT : DROPDOWN_SELECTED_FG_DARK
            end

            def dropdown_muted_fg
              light_mode? ? DROPDOWN_MUTED_FG_LIGHT : DROPDOWN_MUTED_FG_DARK
            end

            def cursor_bg
              light_mode? ? SOURCE_CURSOR_BG_LIGHT : SOURCE_CURSOR_BG_DARK
            end

            def cursor_fg
              light_mode? ? CURSOR_FG_LIGHT : CURSOR_FG_DARK
            end

            def light_mode?
              UI::MENU_SURFACE_BG == UI::MENU_SURFACE_BG_LIGHT
            end

            def reset
              Shoko::Shared::Terminal::Ansi::RESET
            end
          end
        end
      end
    end
  end
end
