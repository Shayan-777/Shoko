# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Article content rendering helpers for the RSS reader screen.
          module RssReaderScreenComponentContentSupport
            private

            def render_content_pane(surface, bounds, box)
              draw_box(
                surface,
                bounds,
                box,
                label: content_box_label,
                border_color: pane_border_color(:content),
                label_color: pane_label_color(:content)
              )
              render_content_body(surface, bounds, box, selected_article_hash)
            end

            def render_content_body(surface, bounds, box, article)
              return render_box_empty(surface, bounds, box, 'Select an article to read.') unless article

              inner_width = [box.width - 4, 1].max
              inner_height = [box.height - 2, 1].max
              lines = build_article_lines(article, inner_width)
              max_offset = [lines.length - inner_height, 0].max
              offset = current_scroll.clamp(0, max_offset)

              payload = { box: box, lines: lines, offset: offset, inner_height: inner_height }
              write_article_lines(surface, bounds, payload)
              render_content_scroll_badge(surface, bounds, payload) if max_offset.positive?
            end

            def build_article_lines(article, width)
              [
                *highlight_lines(article[:title].to_s, width),
                meta_line("#{article_state_label(article)}  #{article[:feed_title]}".strip, width),
                meta_line("#{article[:published_label]}  #{compact_url(article[:url])}".strip, width),
                '',
                *article_body_lines(article, width),
              ]
            end

            def write_article_lines(surface, bounds, payload)
              visible = payload[:lines][payload[:offset], payload[:inner_height]] || []
              visible.each_with_index do |line, index|
                surface.write(bounds, payload[:box].row + 1 + index, payload[:box].col + 2, line)
              end
            end

            def render_content_scroll_badge(surface, bounds, payload)
              badge = content_scroll_badge(payload)
              col = payload[:box].col + payload[:box].width
              col -= Shoko::Shared::Terminal::TextMetrics.visible_length(badge) + 2
              surface.write(
                bounds,
                payload[:box].row + payload[:box].height - 2,
                col,
                "#{@tokens.dim}#{badge}#{@tokens.reset}"
              )
            end

            def article_body_lines(article, width)
              wrap_text(article_body_text(article), width).map do |line|
                "#{@tokens.primary}#{line}#{@tokens.reset}"
              end
            end

            def article_body_text(article)
              content_text = article[:content].to_s.strip
              content_text.empty? ? article[:summary].to_s : content_text
            end

            def highlight_lines(text, width)
              wrap_text(text.to_s, width).map do |line|
                "#{Shoko::Shared::Terminal::Ansi::BOLD}#{@tokens.primary}#{line}#{@tokens.reset}"
              end
            end

            def meta_line(text, width)
              clipped = Shoko::Shared::Terminal::TextMetrics.truncate_to(text.to_s, width)
              "#{@tokens.dim}#{clipped}#{@tokens.reset}"
            end

            def article_state_label(article)
              parts = []
              parts << 'UNREAD' if article[:read] != true
              parts << 'STARRED' if article[:starred] == true
              parts.empty? ? 'READ' : parts.join(' · ')
            end

            def compact_url(url)
              value = url.to_s.strip
              return '' if value.empty?

              value.sub(%r{\Ahttps?://}, '')
            end

            def content_scroll_badge(payload)
              line_count = payload[:lines].length
              offset = payload[:offset]
              inner_height = payload[:inner_height]
              "#{offset + 1}-#{[offset + inner_height, line_count].min}/#{line_count}"
            end
          end
        end
      end
    end
  end
end
