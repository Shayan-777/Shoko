# frozen_string_literal: true

require_relative '../base_component'
require 'shoko/shared/terminal/ansi'
require 'shoko/shared/terminal/text_metrics'
require 'shoko/shared/index_range'
require 'shoko/shared/hash_normalizer'
require_relative '../menu_design/canvas_frame'
require_relative '../menu_design/canvas_list'
require_relative '../menu_design/canvas_scrollbar'
require_relative '../menu_design/icon_set'
require_relative '../menu_design/view_accents'
require_relative '../status_bar/palette'
require_relative '../ui/text_utils'
require_relative 'rss_article_layout'
require_relative 'reading_span_highlighter'
require_relative 'reading_find'
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
            # Blank columns between the prose and the scrollbar, matching the
            # canvas list. The column is reserved whether or not the bar is
            # currently drawn, so the measure does not reflow as an article
            # crosses the "needs scrolling" threshold mid-read.
            READING_RIGHT_GAP = 2
            # What separates one word from the next when right-clicking picks
            # a word out of the prose.
            WORD_BREAK = /[\s[[:punct:]]]/
            # The actions offered over a selection, in the book reader's order.
            CONTEXT_ACTIONS = [
              { label: 'Copy', intent: :rss_reader_copy_selection },
              { label: 'Look Up', intent: :rss_reader_lookup_selection },
              { label: 'Translate', intent: :rss_reader_translate_selection },
              { label: 'Annotate', intent: :rss_reader_annotate_selection },
            ].freeze
            CONTEXT_MENU_PAD = 2
            # Characters kept either side of a selection so an annotation can
            # be re-located in the article later.
            ANCHOR_CONTEXT = 60

            def initialize(menu_state_reader: nil, menu_hit_registry: nil, menu_visual_profile: nil)
              super()
              @menu_state_reader = menu_state_reader
              @menu_hit_registry = menu_hit_registry
              @menu_visual_profile = menu_visual_profile
            end

            def preferred_height(_available_height)
              :fill
            end

            # ----- reading-pane text geometry -------------------------------
            #
            # The pane draws the article as numbered rows (ReadingLine), so a
            # terminal position resolves to a character in the article's
            # selectable stream and back again. These are what the mouse
            # handler drives selection with; they mirror the geometry the
            # renderer just used, so a hit always lands where the reader sees.

            # @return [Integer, nil] character index, or nil off the prose
            def reading_hit(column, row, bounds)
              geometry = reading_geometry(bounds)
              return nil unless geometry

              line = visible_line_at(geometry, row)
              return nil unless line&.selectable?

              line.index + character_offset(line, column - geometry[:content_x])
            end

            # @return [Hash, nil] { start_index:, end_index: } over the stream
            def reading_selection_from_points(start_column:, start_row:, end_column:, end_row:, bounds:)
              first = reading_hit(start_column, start_row, bounds)
              last = reading_hit(end_column, end_row, bounds)
              return nil unless first && last

              start_index, end_index = [first, last].minmax
              return nil if start_index == end_index

              # Mouse positions name cells, not the boundary before a cell.
              # Include the grapheme under the far endpoint just as the book
              # reader's trailing selection anchor does.
              geometry = reading_geometry(bounds)
              end_index = next_grapheme_index(reading_stream(geometry[:lines]), end_index)
              { start_index: start_index, end_index: end_index }
            end

            # @return [String] the selected text, '' when nothing is selected
            def reading_selection_text(selection, bounds)
              geometry = reading_geometry(bounds)
              return '' unless geometry && selection

              start_index, end_index = Shoko::Shared::IndexRange.ordered(selection)
              reading_stream(geometry[:lines])[start_index...end_index].to_s
            end

            # The selection as it is stored in state: its span plus the text it
            # resolves to and the words either side.
            #
            # The span alone is meaningless outside this screen — it indexes a
            # stream produced by *this* wrapping — so the text is resolved here,
            # at selection time. Everything downstream (copy, lookup, translate,
            # the annotation's anchor) then works from plain text and never
            # needs to know how the article was laid out.
            def reading_selection_payload(selection, bounds)
              geometry = reading_geometry(bounds)
              return nil unless geometry && selection

              stream = reading_stream(geometry[:lines])
              from, to = Shoko::Shared::IndexRange.ordered(selection)
              text = stream[from...to].to_s
              return nil if text.strip.empty?

              {
                start_index: from, end_index: to, text: text,
                prefix: stream[[from - ANCHOR_CONTEXT, 0].max...from].to_s,
                suffix: stream[to, ANCHOR_CONTEXT].to_s
              }
            end

            # True when the pane is showing an article that can be interacted with.
            def reading_pane_active?
              reading? && selected_article_hash ? true : false
            end

            # The word under a stream index, so right-clicking outside the
            # selection still has something to act on.
            # @return [Hash, nil] { start_index:, end_index: }
            def reading_word_at(index, bounds)
              geometry = reading_geometry(bounds)
              return nil unless geometry

              stream = reading_stream(geometry[:lines])
              return nil if index >= stream.length || WORD_BREAK.match?(stream[index].to_s)

              from = index
              from -= 1 while from.positive? && !WORD_BREAK.match?(stream[from - 1])
              to = index
              to += 1 while to < stream.length && !WORD_BREAK.match?(stream[to])
              { start_index: from, end_index: to }
            end

            # @return [Hash, nil] the action under a position in the actions menu
            def context_menu_hit(column, row, bounds)
              box = context_menu_box(bounds)
              return nil unless box

              index = row - box[:row]
              return nil unless index >= 0 && index < CONTEXT_ACTIONS.length
              return nil unless column >= box[:column] && column < box[:column] + box[:width]

              CONTEXT_ACTIONS[index]
            end

            def do_render(surface, bounds)
              @current_bounds = bounds
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
              @menu_hit_registry
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
              if reading?
                return 'drag selects · right-click acts · Y copy · D look up · T translate · M note · F find · ESC menu'
              end
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

              render_article_blocks(surface, bounds, frame, top: list_top, height: list_height)
            end

            def render_article_blocks(surface, bounds, frame, top:, height:)
              list = MenuDesign::CanvasList.new(surface, bounds, frame: frame, hits: hits)
              list.register_wheel(top: top, height: height, action: { type: :list_wheel, list: :rss_articles })
              capacity = [height / ARTICLE_BLOCK_ROWS, 1].max
              offset = window_offset(article_entries.length, capacity, current_article_index)
              render_visible_articles(list, top, capacity, offset)
              list.render_scrollbar(top: top, height: height, total: article_entries.length,
                                    visible: capacity, offset: offset)
            end

            def render_visible_articles(list, top, capacity, offset)
              capacity.times do |slot|
                article = article_entries[offset + slot]
                break unless article

                render_article_block(list, article, index: offset + slot, row: top + (slot * ARTICLE_BLOCK_ROWS))
              end
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
              lines = reading_lines(article, reading_width(frame))
              height = reading_height(frame, top, lines.length)
              offset = reading_offset(lines, height)
              write_reading_window(surface, bounds, frame, lines: lines, offset: offset, top: top, height: height)
              MenuDesign::CanvasScrollbar.render(
                surface: surface, bounds: bounds, frame: frame, top: top, height: height,
                total: lines.length, visible: height, offset: offset
              )
              render_reading_position(frame, lines.length, offset, height)
              render_context_menu(surface, bounds, frame)
              register_reading_wheel(frame, top, height)
            end

            # A small card of actions anchored where the reader right-clicked,
            # kept inside the pane so it is never drawn off the edge.
            def render_context_menu(surface, bounds, frame)
              box = context_menu_box(bounds)
              return unless box

              CONTEXT_ACTIONS.each_with_index do |action, index|
                label = " #{action[:label]}".ljust(box[:width])
                surface.write(bounds, box[:row] + index, box[:column],
                              frame.seg(label, Palette::LANDING_TITLE_FG, background: Palette::LIST_SELECTED_BG))
              end
            end

            # @return [Hash, nil] :row, :column, :width of the actions card
            def context_menu_box(bounds)
              anchor = Shoko::Shared::HashNormalizer.symbolize_keys(menu_state_reader&.rss_context_menu)
              return nil unless anchor

              width, rows = context_menu_dimensions
              {
                row: anchor[:anchor_row].to_i.clamp(1, [bounds.height - rows, 1].max),
                column: anchor[:anchor_column].to_i.clamp(1, [bounds.width - width, 1].max),
                width: width,
              }
            end

            def context_menu_dimensions
              [CONTEXT_ACTIONS.map { |action| action[:label].length }.max + CONTEXT_MENU_PAD,
               CONTEXT_ACTIONS.length]
            end

            # The position badge is a full-width line on the last body row, so a
            # scrolling article's window stops one row short of it. Without
            # that the badge covers both the final line of prose and the foot
            # of the scrollbar. Reserving a row can only ever keep an article
            # scrolling, never make it fit, so the decision cannot oscillate.
            # The same measurements the last render used, recomputed from the
            # bounds so a hit test cannot disagree with what is on screen.
            def current_bounds
              @current_bounds || Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 80, height: 24)
            end

            def reading_geometry(bounds)
              return nil unless reading_pane_active?

              frame = MenuDesign::CanvasFrame.new(nil, bounds)
              lines = reading_lines(selected_article_hash, reading_width(frame))
              top = frame.body_top
              height = reading_height(frame, top, lines.length)
              {
                lines: lines, top: top, height: height, content_x: frame.content_x,
                offset: reading_offset(lines, height)
              }
            end

            def visible_line_at(geometry, row)
              index = geometry[:offset] + (row - geometry[:top])
              return nil unless index >= geometry[:offset] && index < geometry[:offset] + geometry[:height]

              geometry[:lines][index]
            end

            # Maps a column within the content area onto a character of the
            # row's prose, stepping by display width so wide glyphs count once.
            def character_offset(line, local_column)
              target = local_column - line.column
              return 0 if target <= 0

              width = 0
              character_index = 0
              line.text.each_grapheme_cluster do |cluster|
                cell = [TextMetrics.visible_length(cluster), 1].max
                index = character_index
                return index if target < width + cell

                width += cell
                character_index += cluster.length
              end
              line.text.length
            end

            # Rows joined the way they were numbered, so a stream index means
            # the same character here as it does in a ReadingLine.
            def reading_stream(lines)
              lines.map(&:text).join("\n")
            end

            def next_grapheme_index(stream, index)
              cluster = stream[index..]&.each_grapheme_cluster&.first
              index + (cluster&.length || 0)
            end

            def reading_height(frame, top, total)
              available = [frame.body_bottom - top + 1, 1].max
              return available if total <= available

              [available - 1, 1].max
            end

            # The stored scroll, except that a targeted find match pulls the
            # window to itself so pressing n always shows the hit.
            def reading_offset(lines, height)
              scroll = current_scroll
              found = find_matches(lines)
              unless found.empty?
                match = found[ReadingFind.wrap_index(find_index, found.length)]
                scroll = ReadingFind.scroll_to(match, lines, scroll: scroll, visible: height) if match
              end
              scroll.clamp(0, [lines.length - height, 0].max)
            end

            def reading_width(frame)
              reserved = MenuDesign::CanvasScrollbar::WIDTH + READING_RIGHT_GAP
              (frame.content_width - reserved).clamp(1, READING_MAX_WIDTH)
            end

            def write_reading_window(surface, bounds, frame, lines:, offset:, top:, height:)
              spans = reading_spans(lines)
              (lines[offset, height] || []).each_with_index do |line, index|
                segments = ReadingSpanHighlighter.call(line, spans)
                surface.write(bounds, top + index, frame.content_x,
                              frame.compose(left: segments, right: []))
              end
            end

            # What is painted over the prose: the live selection, plus every
            # find match with the current one picked out.
            def reading_spans(lines)
              spans = []
              selection = reading_selection
              if selection
                from, to = Shoko::Shared::IndexRange.ordered(selection)
                spans << { range: from..to, style: ReadingSpanHighlighter::SELECTION }
              end
              spans.concat(annotation_spans(lines))
              spans.concat(find_match_spans(lines))
              spans
            end

            # Notes made on this article show where they were made. The quote
            # is located in the current stream rather than stored as an offset,
            # so a note survives the article being re-fetched or re-wrapped.
            def annotation_spans(lines)
              quotes = Array(menu_state_reader&.rss_annotations)
              return [] if quotes.empty?

              stream = reading_stream(lines)
              quotes.filter_map do |record|
                quote = Shoko::Shared::HashNormalizer.symbolize_keys(record)&.dig(:quote).to_s
                next if quote.empty?

                at = stream.index(quote)
                next unless at

                { range: at...(at + quote.length), style: ReadingSpanHighlighter::ANNOTATION }
              end
            end

            def reading_selection
              value = menu_state_reader&.rss_selection
              Shoko::Shared::HashNormalizer.symbolize_keys(value)
            end

            # Every match underlined, the one the reader is on reversed too, so
            # its position is obvious without losing sight of the others.
            def find_match_spans(lines)
              found = find_matches(lines)
              return [] if found.empty?

              current = ReadingFind.wrap_index(find_index, found.length)
              found.each_with_index.map do |range, index|
                style = index == current ? ReadingSpanHighlighter::CURRENT_MATCH : ReadingSpanHighlighter::MATCH
                { range: range, style: style }
              end
            end

            def find_matches(lines)
              query = find_query
              return @find_total = [] if query.empty?

              key = [lines.object_id, query.downcase]
              found = if @find_matches_key == key
                        @find_matches
                      else
                        @find_matches_key = key
                        @find_matches = ReadingFind.matches(reading_stream(lines), query)
                      end
              @find_total = found.length
              found
            end

            def find_query = menu_state_reader&.rss_find_query.to_s

            def find_index = menu_state_reader&.rss_find_index.to_i

            def find_active? = menu_state_reader&.rss_find_active == true

            # Laying an article out costs milliseconds — every block is
            # re-wrapped, and display width is measured per word — while
            # scrolling only changes which slice of the result is shown. The
            # rendered lines are therefore memoized per article and measure, so
            # a scroll step is a window slice rather than a full relayout.
            # Keyed on the content itself, so a re-synced article re-lays out.
            def reading_lines(article, width)
              key = reading_lines_key(article, width)
              return @reading_lines if @reading_lines_key == key

              @reading_lines_key = key
              @reading_lines = build_reading_lines(article, width)
            end

            def reading_lines_key(article, width)
              [
                article[:id],
                width,
                article[:title].to_s.hash,
                article[:author].to_s.hash,
                article[:published_label].to_s.hash,
                Array(article[:content_blocks]).hash,
                article[:content].to_s.hash,
                article[:summary].to_s.hash,
              ]
            end

            def build_reading_lines(article, width)
              rows = [
                *wrap_words(article[:title].to_s, width).map { |line| [[line, Palette::LANDING_TITLE_FG]] },
                [[reading_meta(article), Palette::LANDING_DIM_FG]],
              ]
              RssArticleLayout.index_rows(
                rows.map { |segments| { content: segments, text: segments.map(&:first).join, column: 0 } } +
                article_body_rows(article, width) +
                reading_footer_rows(article)
              )
            end

            # Structured blocks when the article has them, so headings, lists,
            # quotes, code and inline emphasis survive to the screen. Articles
            # cached before blocks existed still render from their flat text.
            def article_body_rows(article, width)
              blocks = article[:content_blocks]
              return [blank_row, *RssArticleLayout.new(width: width).rows(blocks)] if Array(blocks).any?

              plain = wrap_words(article_body_text(article), width).map do |line|
                { content: [[line, Palette::LANDING_TEXT_FG]], text: line, column: 0 }
              end
              [blank_row, *plain]
            end

            def blank_row = { prefix: [], content: [], text: '', column: 0 }

            def reading_meta(article)
              [article[:feed_title], article[:author], article[:published_label]]
                .map(&:to_s).reject(&:empty?).join('  ·  ')
            end

            def reading_footer_rows(article)
              url = article[:url].to_s.strip.sub(%r{\Ahttps?://}, '')
              return [] if url.empty?

              [blank_row, { content: [[url, Palette::LANDING_DIM_FG]], text: url, column: 0 }]
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
              render_visible_feeds(list, list_top, height, offset)
              list.render_scrollbar(top: list_top, height: height, total: feed_entries.length,
                                    visible: height, offset: offset)
            end

            def render_visible_feeds(list, list_top, height, offset)
              height.times do |slot|
                feed = feed_entries[offset + slot]
                break unless feed

                render_feed_row(list, feed, index: offset + slot, row: list_top + slot)
              end
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

            def selected_article_hash
              opened = Shoko::Shared::HashNormalizer.symbolize_keys(menu_state_reader&.rss_open_article)
              selected_id = menu_state_reader&.rss_selected_article_id.to_s
              return opened if opened && opened[:id].to_s == selected_id

              article_entries[current_article_index]
            end

            def current_scroll = (menu_state_reader&.rss_content_scroll || 0).to_i
            def zen_mode? = menu_state_reader&.rss_zen_mode == true
            def feed_input_mode? = menu_state_reader&.mode == :rss_reader_feed_input
            def filter_mode? = menu_state_reader&.mode == :rss_reader_filter
            def overlay_mode? = feed_input_mode? || filter_mode? || find_mode?
            def find_mode? = menu_state_reader&.mode&.to_sym == :rss_reader_find
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

            attr_reader :menu_state_reader

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
              return find_status_message if find_mode? || (find_active? && reading?)

              menu_state_reader&.rss_message.to_s
            end

            # The query as typed, with how many matches it has and which one is
            # current, so n/N always has a visible reference.
            def find_status_message
              query = find_query
              return 'find: ' if query.empty?

              "find: #{query}#{find_counter}"
            end

            # Derived on demand rather than remembered from the body render:
            # the status line is drawn BEFORE the article, so a remembered count
            # would always be one frame stale.
            def find_counter
              total = current_find_matches.length
              return '  ·  no matches' if total.zero?

              "  ·  #{ReadingFind.wrap_index(find_index, total) + 1}/#{total}"
            end

            def current_find_matches
              article = selected_article_hash
              return [] unless article

              find_matches(reading_lines(article, reading_width(MenuDesign::CanvasFrame.new(nil, current_bounds))))
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
