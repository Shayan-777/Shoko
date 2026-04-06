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
                overlay_palette[:panel_bg]
              end

              def quote_bg
                overlay_palette[:quote_bg]
              end

              def panel_fg
                overlay_palette[:panel_fg]
              end

              def panel_fg_emphasis
                overlay_palette[:panel_fg_emphasis]
              end

              def glass_fg
                overlay_palette[:glass_fg]
              end

              def spell_menu_bg
                overlay_palette[:spell_menu_bg]
              end

              def spell_menu_selected_bg
                overlay_palette[:spell_menu_selected_bg]
              end

              def spell_menu_fg
                overlay_palette[:spell_menu_fg]
              end

              def spell_menu_selected_fg
                overlay_palette[:spell_menu_selected_fg]
              end

              def spell_menu_kind_fg
                overlay_palette[:spell_menu_kind_fg]
              end

              def spell_menu_muted_fg
                overlay_palette[:spell_menu_muted_fg]
              end

              def backdrop_fg
                overlay_palette[:backdrop_fg]
              end

              def color_mode
                @color_mode
              end

              def overlay_palette
                Adapters::Ui::Constants::ComponentPalettes.fetch(:annotation_editor_overlay, color_mode)
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
