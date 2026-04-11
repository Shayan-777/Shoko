# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Prompt overlay helpers for add-feed and filter input in the RSS reader screen.
          module RssReaderScreenComponentOverlaySupport
            private

            def render_prompt_overlay(surface, bounds, layout)
              box = overlay_box(layout)
              draw_overlay_box(surface, bounds, box)
              write_overlay_lines(surface, bounds, box)
            end

            def overlay_box(layout)
              width = overlay_width(layout[:content_width])
              col = layout[:indent] + ((layout[:content_width] - width) / 2).floor
              row = overlay_row(layout)
              Ui::BoxDrawer::BoxSpec.new(row, col, self.class::OVERLAY_HEIGHT, width)
            end

            def overlay_input_line(width)
              text = overlay_text
              cursor = overlay_cursor.clamp(0, text.length)
              rendered = prompt_prefix + text[0, cursor].to_s + @tokens.cursor_glyph + text[cursor..].to_s
              "#{@tokens.primary}#{Shoko::Shared::Terminal::TextMetrics.truncate_to(rendered, width)}#{@tokens.reset}"
            end

            def overlay_label
              feed_input_mode? ? 'Add Feed' : 'Filter'
            end

            def overlay_prompt
              feed_input_mode? ? 'Paste an RSS or Atom feed URL' : 'Filter by title, author, summary, or feed'
            end

            def overlay_text
              feed_input_mode? ? menu_state_reader&.rss_feed_input.to_s : menu_state_reader&.rss_filter_query.to_s
            end

            def overlay_cursor
              value = feed_input_mode? ? menu_state_reader&.rss_feed_input_cursor : menu_state_reader&.rss_filter_cursor
              value.to_i
            end

            def prompt_prefix
              feed_input_mode? ? 'URL: ' : 'Find: '
            end

            def draw_overlay_box(surface, bounds, box)
              draw_box(
                surface,
                bounds,
                box,
                label: overlay_label,
                border_color: Shoko::Adapters::Ui::Constants::Ui::BORDER_ACCENT,
                label_color: @tokens.accent
              )
            end

            def write_overlay_lines(surface, bounds, box)
              surface.write(bounds, box.row + 1, box.col + 2, "#{@tokens.dim}#{overlay_prompt}#{@tokens.reset}")
              surface.write(bounds, box.row + 2, box.col + 2, overlay_input_line(box.width - 4))
            end

            def overlay_width(content_width)
              [content_width - 8, self.class::OVERLAY_WIDTH].min.clamp(30, self.class::OVERLAY_WIDTH)
            end

            def overlay_row(layout)
              layout[:workspace_top] + [((layout[:workspace_height] - self.class::OVERLAY_HEIGHT) / 2).floor, 0].max
            end
          end
        end
      end
    end
  end
end
