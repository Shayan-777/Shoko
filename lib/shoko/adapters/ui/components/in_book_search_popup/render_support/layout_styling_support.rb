# frozen_string_literal: true

require_relative '../../base_component'

module Shoko
  module Adapters
    module Ui
      module Components
        class InBookSearchPopupComponent < BaseComponent
          module RenderSupport
            # Layout, styling, and backdrop helpers for the in-book search popup.
            module LayoutStylingSupport
              private

              def fill_panel_background(surface, bounds, layout)
                background = panel_bg
                layout.height.times do |offset|
                  row = layout.origin_y + offset
                  backdrop = backdrop_segment(row, layout.origin_x, layout.width)
                  surface.write(bounds, row, layout.origin_x, "#{background}#{backdrop_fg}#{backdrop}#{reset}")
                end
              end

              def overlay_layout(bounds)
                width = @overlay_sizing.width_for(bounds.width)
                height = @overlay_sizing.height_for(bounds.height)
                Ui::OverlayLayout.centered(bounds, width: width, height: height)
              end

              def backdrop_segment(row, col, width)
                @backdrop_overlay.segment(row, col, width)
              end

              def align_left_right(left, right, width)
                left_len = visible_length(left)
                right_len = visible_length(right)
                gap = width - left_len - right_len
                return "#{left}#{' ' * gap}#{right}" if gap >= 1

                clipped_left = truncate_visible(left, [width - right_len - 1, 1].max)
                gap = [width - visible_length(clipped_left) - right_len, 1].max
                "#{clipped_left}#{' ' * gap}#{right}"
              end

              def pad_visible(text, width)
                clipped = truncate_visible(text.to_s, width)
                pad = [width - visible_length(clipped), 0].max
                "#{clipped}#{' ' * pad}"
              end

              def pad_line(text, width, row: nil, col: nil)
                safe = apply_background_reset(text.to_s)
                safe_width = visible_length(safe)
                pad = [width - safe_width, 0].max
                pad_text = if row.nil? || col.nil?
                             ' ' * pad
                           else
                             backdrop_segment(row, col + safe_width, pad)
                           end
                "#{panel_bg}#{safe}#{backdrop_fg}#{pad_text}#{reset}"
              end

              def apply_background_reset(text)
                text.gsub(reset, "#{text_reset}#{panel_bg}")
              end

              def truncate_visible(text, width)
                Shared::Terminal::TextMetrics.truncate_to(text, width)
              rescue Shoko::Error
                Ui::TextUtils.truncate_text(text.gsub(/\e\[[0-9;]*m/, ''), width)
              end

              def visible_length(text)
                Shared::Terminal::TextMetrics.visible_length(text.to_s)
              rescue Shoko::Error
                text.to_s.gsub(/\e\[[0-9;]*m/, '').length
              end

              def style_text(text, color: nil, bold: false, dim: false)
                prefix = +''
                prefix << color.to_s if color
                prefix << Shoko::Shared::Terminal::Ansi::BOLD if bold
                prefix << Shoko::Shared::Terminal::Ansi::DIM if dim
                "#{prefix}#{text}#{text_reset}"
              end

              def text_reset
                "\e[39;22;23;24m"
              end

              def panel_bg
                @color_mode == :light ? PANEL_BG_LIGHT : Adapters::Ui::Constants::Ui::TOOLTIP_BG_DEFAULT
              end

              def panel_fg
                @color_mode == :light ? PANEL_FG_LIGHT : Adapters::Ui::Constants::Ui::TOOLTIP_FG_DEFAULT
              end

              def panel_fg_emphasis
                @color_mode == :light ? PANEL_FG_EMPHASIS_LIGHT : Adapters::Ui::Constants::Ui::TOOLTIP_FG_SELECTED
              end

              def glass_fg
                @color_mode == :light ? GLASS_FG_LIGHT : Adapters::Ui::Constants::Ui::TOOLTIP_GLASS_FG_DEFAULT
              end

              def backdrop_fg
                @color_mode == :light ? BACKDROP_FG_LIGHT : BACKDROP_FG_DARK
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
