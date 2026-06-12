# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require 'shoko/shared/terminal/ansi'
require 'shoko/shared/terminal/text_metrics'
require_relative '../menu_design/master_detail_shell'
require_relative '../menu_design/search_field_renderer'
require_relative '../menu_design/theme_tokens'
require_relative '../menu_design/icon_set'
require_relative '../ui/text_utils'
require 'time'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # RSS reader.
          #
          # Rather than cramming feeds + articles + content into competing panes, it
          # shows one spacious, full-width view at a time and drills between them
          # (Articles -> Reading; H steps back to Feeds), echoing the in-book reader's
          # focused feel. The Articles list is modelled on the in-book search result
          # list the rest of the app uses — roomy multi-row entries (title · summary ·
          # meta) with a left accent stripe on the active entry and a slim scrollbar —
          # so it reads as the same clean, coherent surface. Everything sits in the
          # shared menu shell (brand header, summary, footer); add-feed / filter use a
          # centered field. The keymap is unchanged (ENTER drills in, H steps back,
          # J/K move, 1/2/3 scope, S sync, A add, / filter, R/U/M/V act).
          class RssReaderScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::TextUtils

            Ansi = Shoko::Shared::Terminal::Ansi
            TextMetrics = Shoko::Shared::Terminal::TextMetrics
            Region = Struct.new(:x, :y, :width, :height)

            LIST_MAX_WIDTH = 98
            READING_MAX_WIDTH = 84
            FEEDS_MAX_WIDTH = 64
            ARTICLE_BLOCK_ROWS = 3 # title · summary · meta, like an in-book search result
            SCROLLBAR_GAP = 2
            COUNT_WIDTH = 4

            def initialize(dependencies: nil, menu_visual_profile: nil)
              super()
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
              @tokens = MenuDesign::ThemeTokens.new
            end

            def preferred_height(_available_height)
              :fill
            end

            def do_render(surface, bounds)
              shell = MenuDesign::MasterDetailShell.new(surface, bounds, tokens: @tokens)
              layout = shell.build_layout(detail_visible: false)
              render_frame(shell, layout)
              area = workspace_area(layout)

              if overlay_mode?
                render_input(surface, bounds, area)
              elsif feed_entries.empty?
                render_note(surface, bounds, area, 'No feeds yet — press A to add a feed URL, then S to sync')
              elsif reading?
                render_reading_view(surface, bounds, area)
              elsif focus?(:feeds)
                render_feeds_view(surface, bounds, area)
              else
                render_articles_view(surface, bounds, area)
              end
            end

            private

            # ----- shell chrome -----

            def render_frame(shell, layout)
              shell.render_frame(
                layout: layout,
                title: 'RSS Reader',
                hint: header_hint,
                summary_left: status_message,
                summary_left_color: status_color,
                summary_right: summary_right,
                footer: footer_text
              )
            end

            def workspace_area(layout)
              frame = layout.primary_panel.frame
              Region.new(frame.x, frame.y, frame.width, frame.height)
            end

            # A centered column within the workspace, so each view reads as a calm,
            # well-margined surface rather than edge-to-edge text.
            def content_column(area, max_width)
              width = [area.width, max_width].min
              indent = area.x + [(area.width - width) / 2, 0].max
              [indent, width]
            end

            # ----- articles list (the in-book-search-style result list) -----

            def render_articles_view(surface, bounds, area)
              indent, width = content_column(area, LIST_MAX_WIDTH)
              render_view_heading(surface, bounds, indent, area.y, width,
                                  left: articles_heading, right: article_position_label)
              region = Region.new(indent, area.y + 2, width, [area.height - 2, 1].max)
              return render_note(surface, bounds, region, empty_articles_text) if article_entries.empty?

              render_article_blocks(surface, bounds, region)
            end

            def render_article_blocks(surface, bounds, region)
              capacity = [region.height / ARTICLE_BLOCK_ROWS, 1].max
              total = article_entries.length
              offset = window_offset(total, capacity, current_article_index)
              scrollbar = total > capacity
              text_width = region.width - (scrollbar ? SCROLLBAR_GAP : 0)

              capacity.times do |slot|
                article = article_entries[offset + slot]
                break unless article

                top = region.y + (slot * ARTICLE_BLOCK_ROWS)
                render_article_block(surface, bounds, region.x, top, text_width, article, offset + slot)
              end
              render_scrollbar(surface, bounds, region, total, capacity, offset) if scrollbar
            end

            def render_article_block(surface, bounds, col, row, width, article, index)
              selected = index == current_article_index
              unread = article[:read] != true
              stripe = selection_stripe(selected)
              text_w = [width - stripe_width, 4].max
              surface.write(bounds, row, col, "#{stripe}#{article_title_span(article, selected, unread, text_w)}")
              surface.write(bounds, row + 1, col, "#{stripe}#{dim_span(article_summary(article), text_w)}")
              surface.write(bounds, row + 2, col, "#{stripe}#{article_meta_span(article, text_w)}")
            end

            def article_title_span(article, selected, unread, width)
              style = if selected
                        "#{Ansi::BOLD}#{@tokens.accent}"
                      else
                        unread ? "#{Ansi::BOLD}#{@tokens.primary}" : @tokens.dim
                      end
              "#{style}#{truncate_text(article[:title].to_s, width)}#{@tokens.reset}"
            end

            # "feed · date" with small unread/star state glyphs, the only pops of colour.
            def article_meta_span(article, width)
              base = "#{article[:feed_title]}  ·  #{article[:published_label]}"
              state = article_state_glyphs(article)
              meta_room = [width - (state.empty? ? 0 : 4), 4].max
              meta = "#{@tokens.dim}#{truncate_text(base, meta_room)}#{@tokens.reset}"
              state.empty? ? meta : "#{meta}  #{state}"
            end

            def article_state_glyphs(article)
              glyphs = []
              glyphs << "#{@tokens.accent}#{glyph(:unread)}#{@tokens.reset}" if article[:read] != true
              glyphs << "#{@tokens.warning}#{glyph(:star)}#{@tokens.reset}" if article[:starred] == true
              glyphs.join(' ')
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

            # ----- reading view (book-reader-like) -----

            def render_reading_view(surface, bounds, area)
              indent, width = content_column(area, READING_MAX_WIDTH)
              article = selected_article_hash
              region = Region.new(indent, area.y, width, area.height)
              return render_note(surface, bounds, region, 'Select an article to read') unless article

              lines = reading_lines(article, width)
              inner_h = [area.height, 1].max
              offset = current_scroll.clamp(0, [lines.length - inner_h, 0].max)
              (lines[offset, inner_h] || []).each_with_index do |line, index|
                surface.write(bounds, area.y + index, indent, line)
              end
              render_reading_scroll_hint(surface, bounds, region, lines.length, offset, inner_h)
            end

            def reading_lines(article, width)
              [
                *wrap_styled(article[:title].to_s, width, "#{Ansi::BOLD}#{@tokens.primary}"),
                "#{@tokens.dim}#{truncate_text(reading_meta(article), width)}#{@tokens.reset}",
                "#{@tokens.divider}#{'─' * width}#{@tokens.reset}",
                '',
                *wrap_styled(article_body_text(article), width, @tokens.primary),
                *reading_footer_lines(article, width),
              ]
            end

            def reading_meta(article)
              [article[:feed_title], article[:author], article[:published_label]]
                .map(&:to_s).reject(&:empty?).join('  ·  ')
            end

            def reading_footer_lines(article, width)
              url = compact_url(article[:url])
              return [] if url.empty?

              ['', "#{@tokens.dim}#{truncate_text(url, width)}#{@tokens.reset}"]
            end

            def render_reading_scroll_hint(surface, bounds, region, total, offset, inner_h)
              return unless total > inner_h

              badge = "#{offset + 1}-#{[offset + inner_h, total].min} / #{total}"
              col = region.x + region.width - visible_length(badge)
              surface.write(bounds, region.y + region.height - 1, col, "#{@tokens.dim}#{badge}#{@tokens.reset}")
            end

            def wrap_styled(text, width, style)
              wrap_text(text.to_s, width).map { |line| "#{style}#{line}#{@tokens.reset}" }
            end

            def article_body_text(article)
              content = article[:content].to_s.strip
              content.empty? ? article[:summary].to_s : content
            end

            def compact_url(url)
              url.to_s.strip.sub(%r{\Ahttps?://}, '')
            end

            # ----- feeds list -----

            def render_feeds_view(surface, bounds, area)
              indent, width = content_column(area, FEEDS_MAX_WIDTH)
              render_view_heading(surface, bounds, indent, area.y, width, left: 'Feeds',
                                                                          right: feed_position_label)
              region = Region.new(indent, area.y + 2, width, [area.height - 2, 1].max)
              return render_note(surface, bounds, region, 'No feeds yet') if feed_entries.empty?

              capacity = region.height
              offset = window_offset(feed_entries.length, capacity, current_feed_index)
              capacity.times do |slot|
                feed = feed_entries[offset + slot]
                break unless feed

                render_feed_line(surface, bounds, region.x, region.y + slot, region.width, feed, offset + slot)
              end
            end

            def render_feed_line(surface, bounds, col, row, width, feed, index)
              selected = index == current_feed_index
              stripe = selection_stripe(selected)
              count = feed_count_label(feed)
              name_w = [width - stripe_width - visible_length(count) - 2, 4].max
              name = pad_right(truncate_text(feed[:title].to_s, name_w), name_w)
              surface.write(bounds, row, col,
                            "#{stripe}#{feed_name_span(feed, selected)}#{name}#{@tokens.reset}  " \
                            "#{feed_count_color(feed)}#{count}#{@tokens.reset}")
            end

            def feed_name_span(feed, selected)
              return "#{Ansi::BOLD}#{@tokens.accent}" if selected
              return @tokens.error unless feed[:sync_error].to_s.empty?

              @tokens.primary
            end

            def feed_count_color(feed)
              feed_unread(feed).positive? ? @tokens.accent : @tokens.dim
            end

            def feed_count_label(feed)
              return '!' unless feed[:sync_error].to_s.empty?

              unread = feed_unread(feed)
              unread.positive? ? unread.to_s : (feed[:count] || 0).to_i.to_s
            end

            def feed_unread(feed)
              (feed[:unread_count] || 0).to_i
            end

            def feed_position_label
              count = feed_entries.length
              "#{count} #{count == 1 ? 'feed' : 'feeds'}"
            end

            # ----- shared drawing -----

            def render_view_heading(surface, bounds, col, row, width, left:, right:)
              left_room = [width - visible_length(right) - 2, 4].max
              heading = "#{Ansi::BOLD}#{@tokens.accent}#{truncate_text(left, left_room)}#{@tokens.reset}"
              surface.write(bounds, row, col, heading)
              return if right.to_s.empty?

              surface.write(bounds, row, col + width - visible_length(right), "#{@tokens.dim}#{right}#{@tokens.reset}")
            end

            def render_note(surface, bounds, region, message)
              row = region.y + [region.height / 2, 0].max
              col = region.x + [(region.width - visible_length(message)) / 2, 0].max
              surface.write(bounds, row, col, "#{@tokens.dim}#{truncate_text(message, region.width)}#{@tokens.reset}")
            end

            # A left accent stripe down the active entry (the in-book search signature),
            # or a blank of the same width so every entry's text lines up.
            def selection_stripe(selected)
              return '  ' unless selected

              "#{@tokens.accent}#{stripe_glyph}#{@tokens.reset} "
            end

            def stripe_width = 2

            def dim_span(text, width)
              "#{@tokens.dim}#{truncate_text(text, width)}#{@tokens.reset}"
            end

            # Slim right-edge scrollbar (track + brighter thumb), matching the search list.
            def render_scrollbar(surface, bounds, region, total, capacity, offset)
              rows = region.height
              size = [(capacity.to_f / total * rows).round, 1].max
              room = rows - size
              denom = [total - capacity, 1].max
              start = room <= 0 ? 0 : ((offset.to_f / denom) * room).round.clamp(0, room)
              col = region.x + region.width - 1
              rows.times do |i|
                in_thumb = i >= start && i < start + size
                color = in_thumb ? @tokens.accent : @tokens.divider
                surface.write(bounds, region.y + i, col, "#{color}#{scroll_glyph}#{@tokens.reset}")
              end
            end

            # Keep the selected entry within the visible window (centred-ish, clamped).
            def window_offset(total, capacity, selected)
              return 0 if total <= capacity

              (selected - (capacity / 2)).clamp(0, total - capacity)
            end

            # ----- input overlay (add feed / filter) -----

            def render_input(surface, bounds, area)
              row = area.y + [(area.height / 2) - 1, 0].max
              centered(surface, bounds, area, row, "#{@tokens.heading}#{overlay_label}#{@tokens.reset}")
              centered(surface, bounds, area, row + 1, "#{@tokens.dim}#{overlay_prompt}#{@tokens.reset}")
              render_input_field(surface, bounds, area, row + 3)
            end

            def render_input_field(surface, bounds, area, row)
              width = [area.width / 2, 40].max.clamp(30, [area.width - 4, 30].max)
              indent = area.x + [(area.width - width) / 2, 0].max
              MenuDesign::SearchFieldRenderer.new(surface, bounds, tokens: @tokens).render(
                label: '', query: overlay_text, cursor: overlay_cursor,
                row: row, indent: indent, width: width, active: true, compact: true
              )
            end

            def centered(surface, bounds, area, row, text)
              col = area.x + [(area.width - visible_length(text)) / 2, 0].max
              surface.write(bounds, row, col, text)
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

            # ----- labels, glyphs, header/summary/footer -----

            def overlay_label = feed_input_mode? ? 'Add Feed' : 'Filter Articles'
            def overlay_prompt = feed_input_mode? ? 'Paste an RSS or Atom feed URL' : 'Filter by title, author, or feed'

            def overlay_text
              raw = feed_input_mode? ? menu_state_reader&.rss_feed_input : menu_state_reader&.rss_filter_query
              raw.to_s
            end

            def overlay_cursor
              (feed_input_mode? ? menu_state_reader&.rss_feed_input_cursor : menu_state_reader&.rss_filter_cursor).to_i
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

            def stripe_glyph = MenuDesign::IconSet.ascii_icons? ? '|' : '▌'
            def scroll_glyph = MenuDesign::IconSet.ascii_icons? ? '|' : '█'

            def header_hint
              return 'ENTER apply · ESC cancel' if overlay_mode?
              return 'H back · J/K scroll' if reading?
              return 'ENTER open · ESC back' if focus?(:feeds)

              'ENTER read · H feeds · S sync'
            end

            def summary_right
              [scope_label, last_synced_label].reject(&:empty?).join('  ·  ')
            end

            def footer_text
              return 'Type the feed URL, then ENTER to subscribe' if feed_input_mode?
              return 'Filtering live as you type · ENTER done' if filter_mode?
              return 'J/K scroll · H back · R read · M star · Q menu' if reading?
              return 'J/K move · ENTER open · A add · D remove · Q menu' if focus?(:feeds)

              'J/K move · ENTER read · H feeds · / filter · 1/2/3 scope · S sync · Q menu'
            end

            def status_message
              menu_state_reader&.rss_message.to_s
            end

            def status_color
              case menu_state_reader&.rss_status&.to_sym
              when :error then @tokens.error
              when :syncing then @tokens.accent
              when :ready then @tokens.success
              else @tokens.dim
              end
            end

            def last_synced_label
              text = menu_state_reader&.rss_last_synced_at.to_s.strip
              return '' if text.empty?

              "Synced #{Time.parse(text).localtime.strftime('%H:%M')}"
            rescue ArgumentError
              unknown_last_synced_label
            end

            def unknown_last_synced_label
              ''
            end

            def visible_length(text)
              TextMetrics.visible_length(text.to_s)
            end
          end
        end
      end
    end
  end
end
