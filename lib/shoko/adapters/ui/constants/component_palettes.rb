# frozen_string_literal: true

require 'shoko/shared/terminal/ansi'
require_relative 'ui'

module Shoko
  module Adapters
    module Ui
      module Constants
        # Canonical component-local palette registry for overlays and popups.
        module ComponentPalettes
          UI = Shoko::Adapters::Ui::Constants::Ui
          ANSI = Shoko::Shared::Terminal::Ansi

          module_function

          def fetch(component, color_mode)
            mode = normalize_color_mode(color_mode)

            case component.to_sym
            when :annotation_editor_overlay
              annotation_editor_overlay(mode)
            when :in_book_search_popup
              in_book_search_popup(mode)
            else
              raise ArgumentError, "unknown component palette: #{component}"
            end
          end

          def normalize_color_mode(mode)
            mode.to_s.strip.downcase == 'light' ? :light : :dark
          end
          private_class_method :normalize_color_mode

          def annotation_editor_overlay(mode)
            return annotation_editor_overlay_light if mode == :light

            {
              panel_bg: UI::TOOLTIP_BG_DEFAULT,
              quote_bg: UI::TOOLTIP_BG_SELECTED,
              panel_fg: UI::TOOLTIP_FG_DEFAULT,
              panel_fg_emphasis: UI::TOOLTIP_FG_SELECTED,
              glass_fg: UI::TOOLTIP_GLASS_FG_DEFAULT,
              spell_menu_bg: "\e[48;2;31;35;53m",
              spell_menu_selected_bg: "\e[48;2;67;74;108m",
              spell_menu_fg: "\e[38;2;211;220;246m",
              spell_menu_selected_fg: "\e[38;2;242;246;255m#{ANSI::BOLD}",
              spell_menu_kind_fg: "\e[38;2;138;180;255m",
              spell_menu_muted_fg: "\e[38;2;125;132;162m",
              backdrop_fg: "\e[38;2;34;38;50m#{ANSI::DIM}",
            }
          end
          private_class_method :annotation_editor_overlay

          def annotation_editor_overlay_light
            {
              panel_bg: "\e[48;2;233;236;241m",
              quote_bg: "\e[48;2;220;226;234m",
              panel_fg: "\e[38;2;32;38;48m",
              panel_fg_emphasis: "\e[38;2;22;56;84m",
              glass_fg: "\e[38;2;116;126;141m#{ANSI::DIM}",
              spell_menu_bg: "\e[48;2;231;236;243m",
              spell_menu_selected_bg: "\e[48;2;210;220;236m",
              spell_menu_fg: "\e[38;2;43;50;63m",
              spell_menu_selected_fg: "\e[38;2;22;40;57m#{ANSI::BOLD}",
              spell_menu_kind_fg: "\e[38;2;22;102;136m",
              spell_menu_muted_fg: "\e[38;2;122;131;149m",
              backdrop_fg: "\e[38;2;224;228;234m#{ANSI::DIM}",
            }
          end
          private_class_method :annotation_editor_overlay_light

          def in_book_search_popup(mode)
            return in_book_search_popup_light if mode == :light

            {
              panel_bg: UI::TOOLTIP_BG_DEFAULT,
              panel_fg: UI::TOOLTIP_FG_DEFAULT,
              panel_fg_emphasis: UI::TOOLTIP_FG_SELECTED,
              glass_fg: UI::TOOLTIP_GLASS_FG_DEFAULT,
              backdrop_fg: "\e[38;2;34;38;50m#{ANSI::DIM}",
            }
          end
          private_class_method :in_book_search_popup

          def in_book_search_popup_light
            {
              panel_bg: "\e[48;2;233;236;241m",
              panel_fg: "\e[38;2;32;38;48m",
              panel_fg_emphasis: "\e[38;2;22;56;84m",
              glass_fg: "\e[38;2;116;126;141m#{ANSI::DIM}",
              backdrop_fg: "\e[38;2;224;228;234m#{ANSI::DIM}",
            }
          end
          private_class_method :in_book_search_popup_light
        end
      end
    end
  end
end
