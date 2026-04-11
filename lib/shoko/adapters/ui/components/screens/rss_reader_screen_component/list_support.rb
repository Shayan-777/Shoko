# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Feed/article list rendering helpers for the RSS reader screen.
          module RssReaderScreenComponentListSupport
            private

            def render_feed_pane(surface, bounds, box)
              render_list_pane(
                surface: surface,
                bounds: bounds,
                box: box,
                label: "Feeds · #{scope_label.upcase}",
                focus: :feeds,
                items: feed_entries,
                selected_index: current_feed_index
              ) { |feed, width| compose_feed_row(feed, width) }
            end

            def render_article_pane(surface, bounds, box)
              draw_article_pane_box(surface, bounds, box)
              return render_empty_article_pane(surface, bounds, box) if article_entries.empty?

              render_list_rows(
                surface: surface,
                bounds: bounds,
                box: box,
                items: article_entries,
                selected_index: current_article_index
              ) { |article, width| compose_article_row(article, width) }
            end

            def render_list_pane(surface:, bounds:, box:, label:, focus:, items:, selected_index:, &row_builder)
              draw_box(
                surface,
                bounds,
                box,
                label: label,
                border_color: pane_border_color(focus),
                label_color: pane_label_color(focus)
              )
              render_list_rows(surface: surface, bounds: bounds, box: box, items: items, selected_index: selected_index,
                               &row_builder)
            end

            def render_list_rows(surface:, bounds:, box:, items:, selected_index:, &row_builder)
              visible_rows = [box.height - 2, 0].max
              return render_box_empty(surface, bounds, box, '') if visible_rows.zero?

              offset, rows = Ui::ListHelpers.slice_visible(items, visible_rows, selected_index)
              rows.each_with_index do |item, index|
                row_data = { box: box, item: item, index: index, offset: offset, selected_index: selected_index }
                payload = list_row_payload(row_data, &row_builder)
                render_list_row(surface, bounds, **payload)
              end
            end

            def render_box_empty(surface, bounds, box, message)
              lines = empty_box_lines(box, message)
              row = empty_box_start_row(box, lines.length)
              lines.each_with_index do |line, index|
                surface.write(bounds, row + index, box.col + 2, "#{@tokens.dim}#{line}#{@tokens.reset}")
              end
            end

            def render_list_row(surface, bounds, row:, col:, width:, text:, selected:, color:)
              content_width = [width - @tokens.selection_slot_width, 1].max
              clipped = pad_right(
                Shoko::Shared::Terminal::TextMetrics.truncate_to(text.to_s, content_width),
                content_width
              )
              rendered = if selected
                           @tokens.style_selected(clipped)
                         else
                           "#{color}#{' ' * @tokens.selection_slot_width}#{clipped}#{@tokens.reset}"
                         end
              surface.write(bounds, row, col, rendered)
            end

            def compose_feed_row(feed, width)
              badge = pad_left(feed_badge(feed), self.class::FEED_BADGE_WIDTH)
              body_width = [width - self.class::FEED_BADGE_WIDTH - 2, 1].max
              title = feed_title_prefix(feed) + truncate_text(feed[:title].to_s, body_width)
              "#{pad_right(title, body_width)}  #{badge}"
            end

            def compose_article_row(article, width)
              marker = article_marker(article)
              date = pad_left(article[:published_label].to_s, self.class::ARTICLE_DATE_WIDTH)
              body_width = [width - self.class::ARTICLE_DATE_WIDTH - marker.length - 3, 1].max
              title = truncate_text(article[:title].to_s, body_width)
              "#{marker} #{pad_right(title, body_width)}  #{date}"
            end

            def feed_title_prefix(feed)
              return '* ' if feed[:key].to_s == self.class::ALL_FEEDS_KEY
              return '! ' if feed[:sync_error].to_s != ''

              '  '
            end

            def feed_badge(feed)
              count = (feed[:count] || 0).to_i
              unread = (feed[:unread_count] || 0).to_i
              return 'ERR' if feed[:sync_error].to_s != ''

              unread.positive? ? "U#{unread}" : count.to_s
            end

            def article_marker(article)
              starred = article[:starred] == true ? '*' : ' '
              unread = article[:read] == true ? ' ' : '!'
              "#{starred}#{unread}"
            end

            def render_empty_article_pane(surface, bounds, box)
              render_box_empty(surface, bounds, box, 'No articles match the current scope.')
            end

            def empty_box_lines(box, message)
              inner_width = [box.width - 4, 1].max
              wrap_text(message.to_s, inner_width)
            end

            def empty_box_start_row(box, line_count)
              box.row + [[box.height - line_count, 1].max / 2, 1].max
            end

            def draw_article_pane_box(surface, bounds, box)
              draw_box(
                surface,
                bounds,
                box,
                label: article_box_label,
                border_color: pane_border_color(:articles),
                label_color: pane_label_color(:articles)
              )
            end

            def list_row_payload(row_data, &)
              {
                row: list_row_number(row_data),
                col: list_row_column(row_data),
                width: list_row_width(row_data),
                text: list_row_text(row_data, &),
                selected: list_row_selected?(row_data),
                color: list_row_color(row_data[:item]),
              }
            end

            def list_row_number(row_data)
              row_data[:box].row + 1 + row_data[:index]
            end

            def list_row_column(row_data)
              row_data[:box].col + 1
            end

            def list_row_width(row_data)
              row_data[:box].width - 2
            end

            def list_row_text(row_data)
              yield(row_data[:item], list_row_width(row_data))
            end

            def list_row_selected?(row_data)
              row_data[:selected_index] == row_data[:offset] + row_data[:index]
            end
          end
        end
      end
    end
  end
end
