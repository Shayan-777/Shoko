# frozen_string_literal: true

require_relative '../../base_component'

module Shoko
  module Adapters
    module Ui
      module Components
        class AnnotationEditorOverlayComponent < BaseComponent
          module RenderSupport
            # Palette and backdrop helpers for the annotation editor overlay.
            module PaletteSupport
              private

              def overlay_layout(bounds)
                width = @overlay_sizing.width_for(bounds.width)
                height = @overlay_sizing.height_for(bounds.height)
                Ui::OverlayLayout.centered(bounds, width: width, height: height)
              end

              def backdrop_segment(row, col, width)
                @backdrop_overlay.segment(row, col, width)
              end

              def panel_bg
                color_mode == :light ? PANEL_BG_LIGHT : Adapters::Ui::Constants::Ui::TOOLTIP_BG_DEFAULT
              end

              def quote_bg
                color_mode == :light ? QUOTE_BG_LIGHT : Adapters::Ui::Constants::Ui::TOOLTIP_BG_SELECTED
              end

              def panel_fg
                color_mode == :light ? PANEL_FG_LIGHT : Adapters::Ui::Constants::Ui::TOOLTIP_FG_DEFAULT
              end

              def panel_fg_emphasis
                color_mode == :light ? PANEL_FG_EMPHASIS_LIGHT : Adapters::Ui::Constants::Ui::TOOLTIP_FG_SELECTED
              end

              def glass_fg
                color_mode == :light ? GLASS_FG_LIGHT : Adapters::Ui::Constants::Ui::TOOLTIP_GLASS_FG_DEFAULT
              end

              def spell_menu_bg
                color_mode == :light ? SPELL_MENU_BG_LIGHT : SPELL_MENU_BG_DARK
              end

              def spell_menu_selected_bg
                color_mode == :light ? SPELL_MENU_SELECTED_BG_LIGHT : SPELL_MENU_SELECTED_BG_DARK
              end

              def spell_menu_fg
                color_mode == :light ? SPELL_MENU_FG_LIGHT : SPELL_MENU_FG_DARK
              end

              def spell_menu_selected_fg
                color_mode == :light ? SPELL_MENU_SELECTED_FG_LIGHT : SPELL_MENU_SELECTED_FG_DARK
              end

              def spell_menu_kind_fg
                color_mode == :light ? SPELL_MENU_KIND_FG_LIGHT : SPELL_MENU_KIND_FG_DARK
              end

              def spell_menu_muted_fg
                color_mode == :light ? SPELL_MENU_MUTED_FG_LIGHT : SPELL_MENU_MUTED_FG_DARK
              end

              def backdrop_fg
                color_mode == :light ? BACKDROP_FG_LIGHT : BACKDROP_FG_DARK
              end

              def color_mode
                @color_mode
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
end
