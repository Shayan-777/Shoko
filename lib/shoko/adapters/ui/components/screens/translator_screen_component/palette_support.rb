# frozen_string_literal: true

require_relative '../../../constants/ui_constants'
require_relative '../../../constants/component_palettes'
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
              return translator_palette[:source_panel_bg] if kind == :source

              translator_palette[:target_panel_bg]
            end

            def panel_accent(kind)
              return translator_palette[:source_accent] if kind == :source

              translator_palette[:target_accent]
            end

            def panel_border_color(kind)
              return panel_accent(kind) if panel_active?(kind)

              "#{panel_accent(kind)}#{DIM}"
            end

            def panel_text_fg
              translator_palette[:panel_text_fg]
            end

            def panel_muted_fg
              translator_palette[:panel_muted_fg]
            end

            def selection_bg
              UI::MENU_SELECTION_BG
            end

            def selection_fg
              UI::MENU_SELECTION_TEXT
            end

            def context_menu_bg
              light_mode? ? translator_palette[:dropdown_bg] : UI::TOOLTIP_BG_DEFAULT
            end

            def context_menu_fg
              light_mode? ? translator_palette[:dropdown_fg] : UI::TOOLTIP_FG_DEFAULT
            end

            def context_menu_disabled_fg
              panel_muted_fg
            end

            def context_menu_border_color
              panel_accent(:source)
            end

            def dropdown_bg
              translator_palette[:dropdown_bg]
            end

            def dropdown_selected_bg
              translator_palette[:dropdown_selected_bg]
            end

            def dropdown_fg
              translator_palette[:dropdown_fg]
            end

            def dropdown_selected_fg
              translator_palette[:dropdown_selected_fg]
            end

            def dropdown_muted_fg
              translator_palette[:dropdown_muted_fg]
            end

            def cursor_bg
              translator_palette[:source_cursor_bg]
            end

            def cursor_fg
              translator_palette[:cursor_fg]
            end

            def light_mode?
              UI::MENU_SURFACE_BG == UI::MENU_SURFACE_BG_LIGHT
            end

            def translator_palette
              mode = light_mode? ? :light : :dark
              Adapters::Ui::Constants::ComponentPalettes.fetch(:translator_screen, mode)
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
