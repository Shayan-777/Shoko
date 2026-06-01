# frozen_string_literal: true

require_relative 'base_component'
require_relative 'ui/overlay_layout'
require_relative 'ui/text_utils'
require_relative '../../../shared/terminal/ansi'
require_relative '../constants/component_palettes'

module Shoko
  module Adapters
    module Ui
      module Components
        # Popup overlay for selected-text translation results.
        class TranslationPopupComponent < BaseComponent
          include Adapters::Ui::Constants::Ui
          include Ui::TextUtils

          PADDING_H = 2
          PADDING_V = 1

          attr_reader :visible, :scroll_offset, :result

          def initialize(color_mode: :dark)
            super()
            @color_mode = normalize_color_mode(color_mode)
            @visible = false
            @scroll_offset = 0
            @result = nil
            @content_lines_cache = {}
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
            clear_content_cache!
          end

          def hide
            @visible = false
            @scroll_offset = 0
            @result = nil
            clear_content_cache!
          end

          def visible?
            @visible
          end

          def update_color_mode(mode)
            @color_mode = normalize_color_mode(mode)
            clear_content_cache!
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
            update_layout_state(layout)
            layout.fill_background(surface, bounds, background: panel_bg)
            context = render_context(surface: surface, bounds: bounds, layout: layout)
            render_frame(context)
            render_content(context)
          end


          private

          def update_layout_state(layout)
            @last_content_width = [layout.inner_width - (PADDING_H * 2), 20].max
            @last_visible_body_lines = [layout.inner_height - 6, 1].max
          end

          def render_context(surface:, bounds:, layout:)
            {
              surface: surface,
              bounds: bounds,
              layout: layout,
              x: layout.inner_x + PADDING_H - 1,
              row: layout.inner_y + PADDING_V - 1,
              width: @last_content_width,
            }
          end


          def overlay_layout(bounds)
            width = @overlay_sizing.width_for(bounds.width)
            height = @overlay_sizing.height_for(bounds.height)
            Ui::OverlayLayout.centered(bounds, width: width, height: height)
          end

          def render_frame(context)
            layout = context[:layout]
            render_horizontal_border(context, row: layout.origin_y, left: '┌', right: '┐')
            render_vertical_borders(context)
            render_horizontal_border(
              context,
              row: layout.origin_y + layout.height - 1,
              left: '└',
              right: '┘'
            )
          end

          def render_content(context)
            row = context[:row]
            write_text(context, row: row, col: context[:x], text: "#{header_fg}Translation#{reset}")
            row += 1
            write_text(context, row: row, col: context[:x], text: metadata_line(context[:width]))
            row += 2

            visible_content_lines(context[:width]).each do |line|
              write_text(context, row: row, col: context[:x], text: line)
              row += 1
            end

            render_footer(context)
          end

          def visible_content_lines(width)
            content_lines(width).drop(@scroll_offset).first(@last_visible_body_lines)
          end

          def render_footer(context)
            layout = context[:layout]
            footer_row = layout.origin_y + layout.height - 2
            write_text(context, row: footer_row, col: context[:x], text: footer_text(context[:width]))
          end

          def render_vertical_borders(context)
            layout = context[:layout]
            rows = (layout.origin_y + 1)...(layout.origin_y + layout.height - 1)
            rows.each do |row|
              write_text(context, row: row, col: layout.origin_x, text: "#{header_fg}│#{reset}")
              write_text(
                context,
                row: row,
                col: layout.origin_x + layout.width - 1,
                text: "#{header_fg}│#{reset}"
              )
            end
          end

          def render_horizontal_border(context, row:, left:, right:)
            layout = context[:layout]
            text = "#{header_fg}#{left}#{'─' * (layout.width - 2)}#{right}#{reset}"
            write_text(context, row: row, col: layout.origin_x, text: text)
          end

          def write_text(context, row:, col:, text:)
            context[:surface].write(context[:bounds], row, col, text)
          end


          def metadata_line(width)
            info = []
            info << "Detected: #{language_code(result&.detected_source_lang || result&.source_lang)}"
            info << "Target: #{language_code(result&.target_lang)}"
            "#{muted_fg}#{pad_right(info.join('   '), width)}#{reset}"
          end

          def content_lines(width)
            @content_lines_cache[content_cache_key(width)] ||= build_content_lines(width)
          end

          def clear_content_cache!
            @content_lines_cache.clear
          end

          def build_content_lines(width)
            [
              section_header('Original', width),
              *body_lines(result&.query.to_s, width),
              blank_line(width),
              section_header(translated_section_label, width),
              *body_lines(translated_section_text, width, error: translation_error?),
            ]
          end

          def content_cache_key(width)
            [result&.object_id, width, @color_mode]
          end

          def translated_section_label
            translation_error? ? 'Error' : 'Translated'
          end

          def translated_section_text
            return result&.error_message.to_s if translation_error?

            result&.translated_text.to_s
          end

          def translation_error?
            result&.error? == true
          end

          def section_header(label, width)
            "#{header_fg}#{pad_right(label, width)}#{reset}"
          end

          def body_lines(text, width, error: false)
            color = error ? error_fg : body_fg
            wrap_text(text.to_s, width).map do |line|
              "#{color}#{pad_right(line, width)}#{reset}"
            end
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


          def panel_bg
            translation_palette[:panel_bg]
          end

          def header_fg
            translation_palette[:header_fg]
          end

          def muted_fg
            translation_palette[:muted_fg]
          end

          def body_fg
            translation_palette[:body_fg]
          end

          def error_fg
            translation_palette[:error_fg]
          end

          def language_code(code)
            value = code.to_s.strip
            value.empty? ? 'auto' : value
          end

          def normalize_color_mode(mode)
            mode.to_s == 'light' ? :light : :dark
          end

          def translation_palette
            Adapters::Ui::Constants::ComponentPalettes.fetch(:translation_popup, @color_mode)
          end

          def reset
            Shoko::Shared::Terminal::Ansi::RESET
          end

        end
      end
    end
  end
end
