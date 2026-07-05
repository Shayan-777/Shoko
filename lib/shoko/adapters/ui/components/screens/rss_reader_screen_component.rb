# frozen_string_literal: true

require_relative '../base_component'
require 'shoko/shared/terminal/ansi'
require 'shoko/shared/terminal/text_metrics'
require_relative '../menu_design/canvas_frame'
require_relative '../menu_design/canvas_list'
require_relative '../menu_design/icon_set'
require_relative '../menu_design/view_accents'
require_relative '../status_bar/palette'
require_relative '../ui/text_utils'
require 'time'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # RSS reader — lavender like the TOC, in the canvas grammar. It
          # keeps its drill-down shape (Feeds -> Articles -> Reading; H steps
          # back) and retells each level in the family language: articles as
          # three-row blocks exactly like in-book search results, feeds as
          # selection-strip rows with unread counts, and the reading view as
          # calm prose on the canvas with a position badge. Add-feed and
          # filter input live in the status bar.
          class RssReaderScreenComponent < BaseComponent
            include Ui::TextUtils

            Palette = StatusBar::Palette
            TextMetrics = Shoko::Shared::Terminal::TextMetrics

            ARTICLE_BLOCK_ROWS = 3 # title · summary · meta, like an in-book search result
            READING_MAX_WIDTH = 84

            def initialize(dependencies: nil, menu_visual_profile: nil)
              super()
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
            end

            def preferred_height(_available_height)
              :fill
            end

            def do_render(surface, bounds)
              frame = MenuDesign::CanvasFrame.new(surface, bounds)
              frame.paint
              frame.render_rule(title: 'RSS Reader', accent: accent, meta: rule_meta)
              render_status_line(frame)
              render_workspace(surface, bounds, frame)
              frame.render_hint(hint_text)
            end

            private

            def accent
              MenuDesign::ViewAccents.for(:rss_reader)
            end

            def hits
              @dependencies.respond_to?(:menu_hit_registry) ? @dependencies.menu_hit_registry : nil
            end

            def render_workspace(surface, bounds, frame)
              if feed_entries.empty?
                render_note(frame, 'No feeds yet — press A to add a feed URL, then S to sync')
              elsif reading?
                render_reading_view(surface, bounds, frame)
              elsif focus?(:feeds)
                render_feeds_view(surface, bounds, frame)
              else
                render_articles_view(surface, bounds, frame)
              end
            end

            # ----- chrome -----

            def rule_meta
              [scope_label.downcase, last_synced_label.downcase].reject(&:empty?).join(' · ')
            end

            def render_status_line(frame)
              message = status_message
              return if message.empty?

              frame.render_status(row: frame.body_top, left: message, left_fg: status_fg)
            end

            def status_rows
              status_message.empty? ? 0 : 2
            end

            def workspace_top(frame)
              frame.body_top + status_rows
            end

            def hint_text
              return 'type in the bar below · ENTER apply · ESC cancel' if overlay_mode?
              return 'J/K scroll · SPACE page · H back · R read · M star · Z zen · ESC menu' if reading?
              return 'ENTER open · A add · D remove · S sync · ESC menu' if focus?(:feeds)

              'ENTER read · H feeds · / filter · 1/2/3 scope · S sync · ESC menu'
            end

            # ----- articles (three-row blocks, the in-book search shape) -----

            def render_articles_view(surface, bounds, frame)
              top = workspace_top(frame)
              height = [frame.body_bottom - top + 1, 0].max
              return if height <= 0

              render_view_heading(frame, top, left: articles_heading, right: article_position_label)
              list_top = top + 2
              list_height = [frame.body_bottom - list_top + 1, 0].max
              return render_note(frame, empty_articles_text) if article_entries.empty?

              render_article_blocks(surface, bounds, frame, list_top, list_height)
            end

            def render_article_blocks(surface, bounds, frame, top, height)
              list = MenuDesign::CanvasList.new(surface, bounds, frame: frame, hits: hits)
              list.register_wheel(top: top, height: height, action: { type: :list_wheel, list: :rss_articles })
              capacity = [height / ARTICLE_BLOCK_ROWS, 1].max
              offset = window_offset(article_entries.length, capacity, current_article_index)
              capacity.times do |slot|
                article = article_entries[offset + slot]
                break unless article

                render_article_block(list, article, index: offset + slot, row: top + (slot * ARTICLE_BLOCK_ROWS))
              end
              list.render_scrollbar(top: top, height: height, total: article_entries.length,
                                    visible: capacity, offset: offset)
            end

            def render_article_block(list, article, index:, row:)
              selected = index == current_article_index
              list.block(
                row: row,
                lines: article_block_lines(article, selected),
                selected: selected,
                action: { type: :list_row, list: :rss_articles, index: index }
              )
            end

            def article_block_lines(article, selected)
              [
                { left: [[article[:title].to_s, article_title_fg(article, selected)]],
                  right: article_state_segments(article) },
                { left: [[article_summary(article), Palette::LANDING_DIM_FG]] },
                { left: [["#{article[:feed_title]} · #{article[:published_label]}", Palette::LANDING_DIM_FG]] },
              ]
            end

            def article_title_fg(article, selected)
              return Palette::LANDING_TITLE_FG if selected
              return Palette::LANDING_TEXT_FG if article[:read] != true

              Palette::LANDING_DIM_FG
            end

            def article_state_segments(article)
              segments = []
              segments << [glyph(:unread), accent] if article[:read] != true
              segments << [' ', nil] if segments.any? && article[:starred] == true
              segments << [glyph(:star), Palette::LIST_MATCH_FG] if article[:starred] == true
              segments
            end

            def article_summary(article)
              text = article[:summary].to_s.strip
              text = article_body_text(article) if text.empty?
              text.tr("\n", ' ').gsub(/\s+/, ' ').strip
            end

            def articles_heading
              "#{current_feed_title} · #{scope_label}"
            end

            def article_position_label
              return '' if article_entries.empty?

              "#{current_article_index + 1} / #{article_entries.length}"
            end

            def empty_articles_text
              case menu_state_reader&.rss_scope&.to_sym
              when :unread then 'No unread articles here'
              when :starred then 'No starred articles yet'
              else 'No articles yet — press S to sync'
              end
            end

            # ----- reading view -----

            def render_reading_view(surface, bounds, frame)
              article = selected_article_hash
              return render_note(frame, 'Select an article to read') unless article

              top = frame.body_top
              height = [frame.body_bottom - top + 1, 1].max
              width = [frame.content_width, READING_MAX_WIDTH].min
              lines = reading_lines(article, width)
              offset = current_scroll.clamp(0, [lines.length - height, 0].max)
              write_reading_window(surface, bounds, frame, lines: lines, offset: offset, top: top, height: height)
              render_reading_position(frame, lines.length, offset, height)
              register_reading_wheel(frame, top, height)
            end

            def write_reading_window(surface, bounds, frame, lines:, offset:, top:, height:)
              (lines[offset, height] || []).each_with_index do |segments, index|
                surface.write(bounds, top + index, frame.content_x,
                              frame.compose(left: segments, right: []))
              end
            end

            def reading_lines(article, width)
              [
                *wrap_words(article[:title].to_s, width).map { |line| [[line, Palette::LANDING_TITLE_FG]] },
                [[reading_meta(article), Palette::LANDING_DIM_FG]],
                [],
                *wrap_words(article_body_text(article), width).map { |line| [[line, Palette::LANDING_TEXT_FG]] },
                *reading_footer_lines(article),
              ]
            end

            def reading_meta(article)
              [article[:feed_title], article[:author], article[:published_label]]
                .map(&:to_s).reject(&:empty?).join('  ·  ')
            end

            def reading_footer_lines(article)
              url = article[:url].to_s.strip.sub(%r{\Ahttps?://}, '')
              return [] if url.empty?

              [[], [[url, Palette::LANDING_DIM_FG]]]
            end

            def render_reading_position(frame, total, offset, height)
              return unless total > height

              badge = "#{offset + 1}-#{[offset + height, total].min} / #{total}"
              frame.render_status(row: frame.body_bottom, left: '', right: badge)
            end

            def register_reading_wheel(frame, top, height)
              return unless hits

              hits.register(
                col: frame.bounds.x, row: frame.bounds.y + top - 1,
                width: frame.bounds.width, height: height,
                action: { type: :list_wheel, list: :rss_reading }
              )
            end

            # ----- feeds -----

            def render_feeds_view(surface, bounds, frame)
              top = workspace_top(frame)
              render_view_heading(frame, top, left: 'Feeds', right: feed_position_label)
              list_top = top + 2
              height = [frame.body_bottom - list_top + 1, 0].max
              return if height <= 0

              list = MenuDesign::CanvasList.new(surface, bounds, frame: frame, hits: hits)
              list.register_wheel(top: list_top, height: height, action: { type: :list_wheel, list: :rss_feeds })
              offset = window_offset(feed_entries.length, height, current_feed_index)
              height.times do |slot|
                feed = feed_entries[offset + slot]
                break unless feed

                render_feed_row(list, feed, index: offset + slot, row: list_top + slot)
              end
              list.render_scrollbar(top: list_top, height: height, total: feed_entries.length,
                                    visible: height, offset: offset)
            end

            def render_feed_row(list, feed, index:, row:)
              selected = index == current_feed_index
              list.row(
                row: row,
                left: [[feed[:title].to_s, feed_name_fg(feed, selected)]],
                right: [feed_count_segment(feed)],
                selected: selected,
                action: { type: :list_row, list: :rss_feeds, index: index }
              )
            end

            def feed_name_fg(feed, selected)
              return Palette::LANDING_TITLE_FG if selected
              return Palette::LANDING_QUIT_FG unless feed[:sync_error].to_s.empty?

              Palette::LANDING_TEXT_FG
            end

            def feed_count_segment(feed)
              return ['!', Palette::LANDING_QUIT_FG] unless feed[:sync_error].to_s.empty?

              unread = (feed[:unread_count] || 0).to_i
              return ["#{unread} unread", accent] if unread.positive?

              [(feed[:count] || 0).to_i.to_s, Palette::LANDING_DIM_FG]
            end

            def feed_position_label
              count = feed_entries.length
              "#{count} #{count == 1 ? 'feed' : 'feeds'}"
            end

            # ----- shared -----

            def render_view_heading(frame, row, left:, right:)
              frame.render_status(row: row, left: left, left_fg: "#{Shoko::Shared::Terminal::Ansi::BOLD}#{accent}",
                                  right: right)
            end

            def render_note(frame, message)
              row = frame.body_top + [frame.body_height / 2, 0].max - 1
              frame.write_line(row, [[message, Palette::LANDING_DIM_FG]])
            end

            def window_offset(total, capacity, selected)
              return 0 if total <= capacity

              (selected - (capacity / 2)).clamp(0, total - capacity)
            end

            # ----- state readers -----

            def feed_entries = Array(menu_state_reader&.rss_feeds)
            def article_entries = Array(menu_state_reader&.rss_articles)
            def selected_article_hash = article_entries[current_article_index]
            def current_scroll = (menu_state_reader&.rss_content_scroll || 0).to_i
            def zen_mode? = menu_state_reader&.rss_zen_mode == true
            def feed_input_mode? = menu_state_reader&.mode == :rss_reader_feed_input
            def filter_mode? = menu_state_reader&.mode == :rss_reader_filter
            def overlay_mode? = feed_input_mode? || filter_mode?
            def reading? = zen_mode? || focus?(:content)

            def current_feed_index
              selected_index_for(feed_entries, :key, menu_state_reader&.rss_selected_feed_key)
            end

            def current_article_index
              selected_index_for(article_entries, :id, menu_state_reader&.rss_selected_article_id)
            end

            def selected_index_for(items, key, preferred)
              value = preferred.to_s
              items.index { |item| item[key].to_s == value } || 0
            end

            def focus?(pane)
              focus = menu_state_reader&.rss_focus&.to_sym
              focus = :articles unless %i[feeds articles content].include?(focus)
              focus == pane
            end

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
            end

            def article_body_text(article)
              content = article[:content].to_s.strip
              content.empty? ? article[:summary].to_s : content
            end

            def current_feed_title
              feed = feed_entries[current_feed_index]
              feed ? feed[:title].to_s : 'All Feeds'
            end

            def scope_label
              case menu_state_reader&.rss_scope&.to_sym
              when :unread then 'Unread'
              when :starred then 'Starred'
              else 'All'
              end
            end

            def glyph(kind)
              ascii = MenuDesign::IconSet.ascii_icons?
              case kind
              when :unread then ascii ? '*' : '●'
              when :star   then ascii ? '*' : '★'
              end
            end

            def status_message
              menu_state_reader&.rss_message.to_s
            end

            def status_fg
              case menu_state_reader&.rss_status&.to_sym
              when :error then Palette::LANDING_QUIT_FG
              when :syncing then Palette::LIST_MATCH_FG
              when :ready then Palette::TRANS_ACCENT_FG
              else Palette::LANDING_DIM_FG
              end
            end

            def last_synced_label
              text = menu_state_reader&.rss_last_synced_at.to_s.strip
              return '' if text.empty?

              "synced #{Time.parse(text).localtime.strftime('%H:%M')}"
            rescue ArgumentError
              unknown_last_synced_label
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
