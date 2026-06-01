# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../../shared/terminal/ansi'
require_relative '../../../../shared/terminal/text_metrics'
require_relative '../menu_design/frame_renderer'
require_relative '../menu_design/layout'
require_relative '../menu_design/status_renderer'
require_relative '../menu_design/theme_tokens'
require_relative '../ui/box_drawer'
require_relative '../ui/list_helpers'
require_relative '../ui/text_utils'
require 'time'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Three-pane RSS workspace with feed list, headline list, and article reader.
          class RssReaderScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::BoxDrawer
            include Ui::TextUtils

            MIN_FEED_WIDTH = 24
            MAX_FEED_WIDTH = 30
            MIN_ARTICLE_HEIGHT = 7
            BOX_GAP = 2
            ROW_GAP = 1
            OVERLAY_HEIGHT = 5
            OVERLAY_WIDTH = 60
            FEED_BADGE_WIDTH = 7
            ARTICLE_DATE_WIDTH = 16
            ALL_FEEDS_KEY = '__all__'

            def initialize(dependencies: nil, menu_visual_profile: nil)
              super()
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
              @tokens = MenuDesign::ThemeTokens.new
            end

            def do_render(surface, bounds)
              layout = layout_metrics(bounds)
              frame = MenuDesign::FrameRenderer.new(surface, bounds, tokens: @tokens)
              frame.render_title(title: 'RSS Reader', hint: header_hint)
              frame.render_divider
              render_status_row(surface, bounds, layout)
              render_workspace(surface, bounds, layout)
              render_prompt_overlay(surface, bounds, layout) if overlay_mode?
              frame.render_footer(text: footer_text)
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def render_workspace(surface, bounds, layout)
              return render_empty_workspace(surface, bounds, layout) if feed_entries.empty?

              if zen_mode?
                render_zen_workspace(surface, bounds, layout)
              else
                render_standard_workspace(surface, bounds, layout)
              end
            end

            def render_empty_workspace(surface, bounds, layout)
              box = Ui::BoxDrawer::BoxSpec.new(layout[:workspace_top], layout[:indent], layout[:workspace_height],
                                               layout[:content_width])
              draw_box(surface, bounds, box, label: 'Reader', border_color: BORDER_PRIMARY, label_color: @tokens.accent)
              render_box_empty(
                surface,
                bounds,
                box,
                'No feeds configured yet. Press A to add a feed URL and S to sync.'
              )
            end

            def render_standard_workspace(surface, bounds, layout)
              render_feed_pane(surface, bounds, layout[:feed_box])
              render_article_pane(surface, bounds, layout[:article_box])
              render_content_pane(surface, bounds, layout[:content_box])
            end

            def render_zen_workspace(surface, bounds, layout)
              box = Ui::BoxDrawer::BoxSpec.new(layout[:workspace_top], layout[:indent], layout[:workspace_height],
                                               layout[:content_width])
              draw_box(
                surface,
                bounds,
                box,
                label: zen_box_label,
                border_color: pane_border_color(:content),
                label_color: pane_label_color(:content)
              )
              render_content_body(surface, bounds, box, selected_article_hash)
            end

            # Article content rendering helpers for the RSS reader screen.
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

            # Layout helpers for the three-pane RSS reader screen.
            def layout_metrics(bounds)
              content_width = MenuDesign::Layout.centered_content_width(bounds, preferred: 98, min: 48,
                                                                                horizontal_padding: 4)
              dimensions = workspace_dimensions(bounds, content_width)
              layout_metadata(content_width, dimensions).merge(workspace_boxes(dimensions))
            end

            def feed_width_for(content_width)
              (content_width * 0.28).floor.clamp(self.class::MIN_FEED_WIDTH, self.class::MAX_FEED_WIDTH)
            end

            def article_height_for(workspace_height)
              max_height = [workspace_height - 4, self.class::MIN_ARTICLE_HEIGHT].max
              (workspace_height * 0.38).floor.clamp(self.class::MIN_ARTICLE_HEIGHT, max_height)
            end

            def workspace_dimensions(bounds, content_width)
              workspace_top = 6
              workspace_height = [bounds.height - workspace_top - 2, 8].max
              feed_width = feed_width_for(content_width)
              article_height = article_height_for(workspace_height)

              {
                indent: MenuDesign::Layout.centered_indent(bounds, content_width),
                workspace_top: workspace_top,
                workspace_height: workspace_height,
                feed_width: feed_width,
                right_width: [content_width - feed_width - self.class::BOX_GAP, 18].max,
                article_height: article_height,
                content_height: [workspace_height - article_height - self.class::ROW_GAP, 3].max,
              }
            end

            def layout_metadata(content_width, dimensions)
              {
                indent: dimensions[:indent],
                content_width: content_width,
                status_row: 4,
                workspace_top: dimensions[:workspace_top],
                workspace_height: dimensions[:workspace_height],
              }
            end

            def workspace_boxes(dimensions)
              {
                feed_box: feed_box(dimensions),
                article_box: article_box(dimensions),
                content_box: content_box(dimensions),
              }
            end

            def feed_box(dimensions)
              Ui::BoxDrawer::BoxSpec.new(
                dimensions[:workspace_top],
                dimensions[:indent],
                dimensions[:workspace_height],
                dimensions[:feed_width]
              )
            end

            def article_box(dimensions)
              Ui::BoxDrawer::BoxSpec.new(
                dimensions[:workspace_top],
                dimensions[:indent] + dimensions[:feed_width] + self.class::BOX_GAP,
                dimensions[:article_height],
                dimensions[:right_width]
              )
            end

            def content_box(dimensions)
              Ui::BoxDrawer::BoxSpec.new(
                dimensions[:workspace_top] + dimensions[:article_height] + self.class::ROW_GAP,
                dimensions[:indent] + dimensions[:feed_width] + self.class::BOX_GAP,
                dimensions[:content_height],
                dimensions[:right_width]
              )
            end

            # Feed/article list rendering helpers for the RSS reader screen.
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

            # Prompt overlay helpers for add-feed and filter input in the RSS reader screen.
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

            # Menu-state readers and derived selection helpers for the RSS reader screen.
            def feed_entries
              Array(menu_state_reader&.rss_feeds)
            end

            def article_entries
              Array(menu_state_reader&.rss_articles)
            end

            def selected_article_hash
              article_entries[current_article_index]
            end

            def current_feed_index
              selected_index_for(feed_entries, :key, menu_state_reader&.rss_selected_feed_key)
            end

            def current_article_index
              selected_index_for(article_entries, :id, menu_state_reader&.rss_selected_article_id)
            end

            def current_scroll
              (menu_state_reader&.rss_content_scroll || 0).to_i
            end

            def normalized_focus
              focus = menu_state_reader&.rss_focus&.to_sym
              return focus if %i[feeds articles content].include?(focus)

              :feeds
            end

            def overlay_mode?
              feed_input_mode? || filter_mode?
            end

            def feed_input_mode?
              menu_state_reader&.mode == :rss_reader_feed_input
            end

            def filter_mode?
              menu_state_reader&.mode == :rss_reader_filter
            end

            def zen_mode?
              menu_state_reader&.rss_zen_mode == true
            end

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
            end

            def selected_index_for(items, key, preferred)
              preferred_value = preferred.to_s
              items.index { |item| item[key].to_s == preferred_value } || 0
            end

            # Header, footer, status, and pane label helpers for the RSS reader screen.
            def render_status_row(surface, bounds, layout)
              MenuDesign::StatusRenderer.new(surface, bounds, tokens: @tokens).render_status(
                row: layout[:status_row],
                indent: layout[:indent],
                left: status_message,
                right: status_detail,
                width: layout[:content_width],
                left_color: status_color
              )
            end

            def status_message
              menu_state_reader&.rss_message.to_s
            end

            def status_detail
              [scope_label, last_synced_label].reject(&:empty?).join('  |  ')
            end

            def status_color
              case menu_state_reader&.rss_status&.to_sym
              when :error then @tokens.error
              when :syncing then @tokens.accent
              when :ready then @tokens.success
              else @tokens.dim
              end
            end

            def header_hint
              return 'ENTER apply  ESC back' if overlay_mode?
              return 'Z zen  H/L pane  J/K move  Q menu' if zen_mode?

              'TAB pane  J/K move  S sync  A add  / filter'
            end

            def footer_text
              return 'Subscribe to a feed URL and press Enter' if feed_input_mode?
              return 'Live filter is active while you type' if filter_mode?
              return '1/2/3 scope  R read  U unread  M star  V unstar  Z exit zen' if zen_mode?

              '1/2/3 scope  R read  U unread  M star  V unstar  D remove feed  Q menu'
            end

            def pane_border_color(focus)
              normalized_focus == focus ? ui_border_accent : ui_border_primary
            end

            def pane_label_color(focus)
              normalized_focus == focus ? @tokens.accent : @tokens.primary
            end

            def list_row_color(item)
              return @tokens.error if item.is_a?(Hash) && item[:sync_error].to_s != ''

              @tokens.primary
            end

            def article_box_label
              title = current_feed_title
              return 'Articles' if title.empty?

              "Articles · #{title}"
            end

            def content_box_label
              article = selected_article_hash
              return 'Content' unless article

              "Content · #{article[:feed_title]}"
            end

            def zen_box_label
              article = selected_article_hash
              article ? "Zen · #{article[:title]}" : 'Zen'
            end

            def current_feed_title
              feed = feed_entries[current_feed_index]
              feed ? feed[:title].to_s : ''
            end

            def scope_label
              case menu_state_reader&.rss_scope&.to_sym
              when :unread then 'Unread'
              when :starred then 'Starred'
              else 'All'
              end
            end

            def last_synced_label
              text = menu_state_reader&.rss_last_synced_at.to_s.strip
              return '' if text.empty?

              "Synced #{Time.parse(text).localtime.strftime('%Y-%m-%d %H:%M')}"
            rescue ArgumentError
              unknown_last_synced_label
            end

            def ui_border_accent
              Shoko::Adapters::Ui::Constants::Ui::BORDER_ACCENT
            end

            def ui_border_primary
              Shoko::Adapters::Ui::Constants::Ui::BORDER_PRIMARY
            end

            def unknown_last_synced_label
              ''
            end
          end
        end
      end
    end
  end
end
