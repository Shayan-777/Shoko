# frozen_string_literal: true

require_relative 'base_component'
require_relative 'ui/overlay_layout'
require_relative 'ui/text_utils'
require_relative '../../../shared/terminal/ansi'

module Shoko
  module Adapters
    module Ui
      module Components
        # Popup overlay for selected-text translation results.
        class TranslationPopupComponent < BaseComponent
          include Adapters::Ui::Constants::Ui
          include Ui::TextUtils

          PANEL_BG_LIGHT = "\e[48;2;233;236;241m"
          PANEL_FG_LIGHT = "\e[38;2;32;38;48m"
          HEADER_FG_LIGHT = "\e[38;2;22;56;84m"
          HEADER_FG_DARK = "\e[38;2;159;196;255m"
          MUTED_FG_LIGHT = "\e[38;2;102;114;128m"
          MUTED_FG_DARK = "\e[38;2;128;138;150m"
          ERROR_FG_LIGHT = "\e[38;2;155;28;28m"
          ERROR_FG_DARK = "\e[38;2;248;113;113m"

          PADDING_H = 2
          PADDING_V = 1

          attr_reader :visible, :scroll_offset, :result

          def initialize(color_mode: :dark)
            super()
            @color_mode = normalize_color_mode(color_mode)
            @visible = false
            @scroll_offset = 0
            @result = nil
            @overlay_sizing = Ui::OverlaySizing.new(
              width_ratio: 0.58,
              width_padding: 10,
              min_width: 48,
              height_ratio: 0.44,
              height_padding: 8,
              min_height: 12
            )
            @last_content_width = 40
            @last_visible_body_lines = 1
          end

          def show(result)
            @result = result
            @scroll_offset = 0
            @visible = true
          end

          def hide
            @visible = false
            @scroll_offset = 0
            @result = nil
          end

          def visible?
            @visible
          end

          def update_color_mode(mode)
            @color_mode = normalize_color_mode(mode)
          end

          def scroll_up
            @scroll_offset = [@scroll_offset - 1, 0].max
          end

          def scroll_down
            @scroll_offset = [@scroll_offset + 1, max_scroll_offset].min
          end

          def do_render(surface, bounds)
            return unless @visible

            layout = overlay_layout(bounds)
            @last_content_width = [layout.inner_width - (PADDING_H * 2), 20].max
            @last_visible_body_lines = [layout.inner_height - 6, 1].max
            layout.fill_background(surface, bounds, background: panel_bg)
            render_frame(surface, bounds, layout)
            render_content(surface, bounds, layout)
          end

          private

          def overlay_layout(bounds)
            width = @overlay_sizing.width_for(bounds.width)
            height = @overlay_sizing.height_for(bounds.height)
            Ui::OverlayLayout.centered(bounds, width: width, height: height)
          end

          def render_frame(surface, bounds, layout)
            write_line(surface, bounds, layout.origin_y, layout.origin_x, '┌', layout.width - 2, '┐', header_fg)
            ((layout.origin_y + 1)...(layout.origin_y + layout.height - 1)).each do |row|
              surface.write(bounds, row, layout.origin_x, "#{header_fg}│#{reset}")
              surface.write(bounds, row, layout.origin_x + layout.width - 1, "#{header_fg}│#{reset}")
            end
            write_line(surface, bounds, layout.origin_y + layout.height - 1, layout.origin_x, '└', layout.width - 2, '┘', header_fg)
          end

          def render_content(surface, bounds, layout)
            row = layout.inner_y + PADDING_V - 1
            x = layout.inner_x + PADDING_H - 1
            width = @last_content_width

            write_text(surface, bounds, row, x, "#{header_fg}Translation#{reset}")
            row += 1
            write_text(surface, bounds, row, x, metadata_line(width))
            row += 2

            visible_lines = content_lines(width).drop(@scroll_offset).first(@last_visible_body_lines)
            visible_lines.each do |line|
              write_text(surface, bounds, row, x, line)
              row += 1
            end

            footer = footer_text(width)
            write_text(surface, bounds, layout.origin_y + layout.height - 2, x, footer)
          end

          def metadata_line(width)
            info = []
            info << "Detected: #{language_code(result&.detected_source_lang || result&.source_lang)}"
            info << "Target: #{language_code(result&.target_lang)}"
            "#{muted_fg}#{pad_right(info.join('   '), width)}#{reset}"
          end

          def content_lines(width)
            lines = []
            lines << section_header('Original', width)
            lines.concat(body_lines(result&.query.to_s, width))
            lines << blank_line(width)
            lines << section_header(result&.error? ? 'Error' : 'Translated', width)
            body = result&.error? ? result&.error_message.to_s : result&.translated_text.to_s
            lines.concat(body_lines(body, width, error: result&.error?))
            lines
          end

          def section_header(label, width)
            "#{header_fg}#{pad_right(label, width)}#{reset}"
          end

          def body_lines(text, width, error: false)
            color = error ? error_fg : body_fg
            wrap_text(text.to_s, width).map { |line| "#{color}#{pad_right(line, width)}#{reset}" }
          end

          def footer_text(width)
            hint = max_scroll_offset.positive? ? 'UP/DOWN scroll  ESC close' : 'ESC close'
            "#{muted_fg}#{pad_right(hint, width)}#{reset}"
          end

          def max_scroll_offset
            [content_lines(@last_content_width).length - @last_visible_body_lines, 0].max
          end

          def blank_line(width)
            ' ' * width
          end

          def write_line(surface, bounds, row, col, left, middle_width, right, color)
            surface.write(bounds, row, col, "#{color}#{left}#{'─' * middle_width}#{right}#{reset}")
          end

          def write_text(surface, bounds, row, col, text)
            surface.write(bounds, row, col, text)
          end

          def panel_bg
            @color_mode == :light ? PANEL_BG_LIGHT : Adapters::Ui::Constants::Ui::TOOLTIP_BG_DEFAULT
          end

          def header_fg
            @color_mode == :light ? HEADER_FG_LIGHT : HEADER_FG_DARK
          end

          def muted_fg
            @color_mode == :light ? MUTED_FG_LIGHT : MUTED_FG_DARK
          end

          def body_fg
            @color_mode == :light ? PANEL_FG_LIGHT : COLOR_TEXT_PRIMARY
          end

          def error_fg
            @color_mode == :light ? ERROR_FG_LIGHT : ERROR_FG_DARK
          end

          def language_code(code)
            value = code.to_s.strip
            value.empty? ? 'auto' : value
          end

          def normalize_color_mode(mode)
            mode.to_s == 'light' ? :light : :dark
          end

          def reset
            Shoko::Shared::Terminal::Ansi::RESET
          end
        end
      end
    end
  end
end
