# frozen_string_literal: true

require 'shoko/shared/terminal/text_metrics'
require_relative '../status_bar/palette'

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          # Styled-span vocabulary shared by the bottom-docked popup family
          # (dictionary lookup, TOC, in-book search, notes, translator). Each
          # host supplies its palette through small private hooks — panel_bg
          # always; panel_dim_fg, panel_rule_fg, panel_body_fg, and
          # panel_field_bg only where the face it renders needs them — and gets
          # the family's span builders, dim/body lines, hairline rule, and
          # width-aware measuring from one place instead of a per-popup copy.
          module PanelSpans
            DIM = "\e[2m"
            STYLE_RESET = "\e[22;23;24m"

            private

            # A span over the panel background.
            def seg(text, foreground)
              "#{StatusBar::Palette::RESET}#{panel_bg}#{foreground}#{text}"
            end

            # A span carrying its own complete style (row backgrounds).
            def cell(text, foreground, background)
              "#{StatusBar::Palette::RESET}#{background}#{foreground}#{text}"
            end

            # A span over the inset editor-field background.
            def field_seg(text, foreground)
              "#{StatusBar::Palette::RESET}#{panel_field_bg}#{foreground}#{text}"
            end

            def dim_line(text)
              "#{DIM}#{panel_dim_fg}#{text}#{STYLE_RESET}"
            end

            # A body line over the panel background: +pad+ columns of left
            # margin, the (already-styled) line — any RESET inside it re-anchors
            # to the panel style — padded out to the width.
            def body_line(text, width, pad: 0)
              base = "#{StatusBar::Palette::RESET}#{panel_bg}#{panel_body_fg}"
              safe = text.to_s.gsub(StatusBar::Palette::RESET, base)
              fill = [width - pad - visible_length(safe), 0].max
              "#{base}#{' ' * pad}#{safe}#{' ' * fill}#{StatusBar::Palette::RESET}"
            end

            # Top hairline rule from pre-styled [span, visible_length] pairs:
            # "── <left> ········· <right> ──". Pass right_cap: '' to let the
            # right span sit flush in the corner with no trailing hairline.
            def render_rule(surface, bounds, row, width, left, right, right_cap: ' ──')
              return if row < 1

              left_span, left_len = left
              right_span, right_len = right
              rule_fg = panel_rule_fg
              fill = [width - left_len - right_len - right_cap.length - 5, 1].max
              text = "#{seg('── ', rule_fg)}#{left_span}#{seg(" #{'·' * fill} ", rule_fg)}" \
                     "#{right_span}#{seg(right_cap, rule_fg)}#{StatusBar::Palette::RESET}"
              surface.write(bounds, row, 1, text)
            end

            def visible_length(text)
              Shoko::Shared::Terminal::TextMetrics.visible_length(text.to_s)
            end

            def truncate(text, width)
              Shoko::Shared::Terminal::TextMetrics.truncate_to(text.to_s, [width.to_i, 0].max)
            end
          end
        end
      end
    end
  end
end
