# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module DictionaryPopup
          # Presentation helpers shared by dictionary popup setup and results views.
          module PresentationSupport
            private

            def overlay_layout(bounds)
              sizing = @setup_mode ? @setup_overlay_sizing : @overlay_sizing
              width = sizing.width_for(bounds.width)
              height = overlay_height(bounds, sizing, width)
              Ui::OverlayLayout.centered(bounds, width: width, height: height)
            end

            def overlay_height(bounds, sizing, width)
              height = sizing.height_for(bounds.height)
              return height unless @setup_mode

              content_width = [width - (self.class::PADDING_H * 2), 12].max
              needed_height = build_setup_lines(content_width).length + (self.class::PADDING_V * 2) + 1
              max_height = [bounds.height - 4, 12].max
              height.clamp(needed_height, max_height)
            end

            def card_line(content, width:, active:)
              background = active ? active_card_bg : card_bg
              safe = apply_background_reset(content, background)
              padding = [width - visible_length(safe) - 2, 0].max
              "#{background} #{safe}#{' ' * padding} #{panel_bg}"
            end

            def style_text(text, color: nil, bold: false, dim: false, italic: false)
              prefix = +''
              prefix << color.to_s if color
              prefix << Shoko::Shared::Terminal::Ansi::BOLD if bold
              prefix << Shoko::Shared::Terminal::Ansi::DIM if dim
              prefix << Shoko::Shared::Terminal::Ansi::ITALIC if italic
              "#{prefix}#{text}#{text_reset}"
            end

            def text_reset
              "\e[39;22;23;24m"
            end

            def pad_line(text, width)
              safe = apply_background_reset(text, panel_bg)
              padding = [width - visible_length(safe), 0].max
              "#{panel_bg}#{safe}#{' ' * padding}#{reset}"
            end

            def apply_background_reset(text, background)
              text.to_s.gsub(reset, "#{text_reset}#{background}")
            end

            def visible_length(text)
              Shared::Terminal::TextMetrics.visible_length(text.to_s)
            rescue Shoko::Error
              text.to_s.gsub(/\e\[[0-9;]*m/, '').length
            end

            def panel_bg
              @color_mode == :light ? self.class::POPUP_BG_LIGHT : self.class::POPUP_BG
            end

            def card_bg
              @color_mode == :light ? self.class::CARD_BG_LIGHT : self.class::CARD_BG
            end

            def active_card_bg
              @color_mode == :light ? "\e[48;5;250m" : "\e[48;5;240m"
            end

            def reset
              Shoko::Shared::Terminal::Ansi::RESET
            end

            def max_scroll_offset
              content_height = @last_content_height || 10
              [@formatted_lines.length - content_height, 0].max
            end
          end
        end
      end
    end
  end
end
