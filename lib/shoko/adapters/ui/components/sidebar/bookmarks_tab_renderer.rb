# frozen_string_literal: true

require_relative '../base_component'
require_relative '../ui/list_helpers'
require_relative '../ui/text_utils'

module Shoko
  module Adapters::Ui::Components
    module Sidebar
      # Bookmarks tab renderer for sidebar
      class BookmarksTabRenderer < BaseComponent
        include Adapters::Ui::Constants::Ui

        ItemCtx = Struct.new(:bookmark, :doc, :index, :selected_index, :y, keyword_init: true)

        def initialize(dependencies)
          super()
          @dependencies = dependencies
          @reader_state_reader = nil
        end

        BoundsMetrics = Struct.new(:x, :y, :width, :height, keyword_init: true)

        def do_render(surface, bounds)
          metrics = metrics_for(bounds)
          bookmarks = reader_state_reader&.bookmarks || []
          doc = resolve_document
          selected_index = sidebar_state_reader&.sidebar_bookmarks_selected || 0

          return render_empty_message(surface, bounds, metrics) if bookmarks.empty?

          render_bookmarks_list(surface, bounds, metrics, bookmarks, doc, selected_index)
        end

        def reader_state_reader
          return @reader_state_reader if @reader_state_reader

          @reader_state_reader = @dependencies&.reader_state_reader
        end

        def sidebar_state_reader
          return @sidebar_state_reader if defined?(@sidebar_state_reader)

          @sidebar_state_reader = @dependencies&.sidebar_state_reader
        end

        private

        def metrics_for(bounds)
          BoundsMetrics.new(x: 1, y: 1, width: bounds.width, height: bounds.height)
        end

        def render_empty_message(surface, bounds, metrics)
          reset = Terminal::ANSI::RESET
          bw = metrics.width
          bh = metrics.height
          messages = [
            'No bookmarks yet',
            '',
            'Press "b" while reading',
            'to add a bookmark',
          ]

          start_y = ((bh - messages.length) / 2) + 1
          messages.each_with_index do |message, i|
            msg_width = Shoko::Shared::Terminal::TextMetrics.visible_length(message)
            x = [(bw - msg_width) / 2, 2].max
            y = start_y + i
            surface.write(bounds, y, x, "#{COLOR_TEXT_DIM}#{message}#{reset}")
          end
        end

        def render_bookmarks_list(surface, bounds, metrics, bookmarks, doc, selected_index)
          # Each bookmark takes 2 lines: title/chapter + snippet
          item_height = 2
          bh = metrics.height
          by = metrics.y
          visible_items = [bh / item_height, 1].max
          visible_start, window_items = Ui::ListHelpers.slice_visible(bookmarks, visible_items, selected_index)
          current_y = by
          end_y = by + bh

          window_items.each_with_index do |bookmark, offset|
            idx = visible_start + offset
            break if current_y + item_height > end_y

            ctx = ItemCtx.new(bookmark: bookmark, doc: doc, index: idx, selected_index: selected_index, y: current_y)
            render_bookmark_item(surface, bounds, metrics, ctx)
            current_y += item_height
          end
        end

        def render_bookmark_item(surface, bounds, metrics, ctx)
          reset = Terminal::ANSI::RESET
          bx = metrics.x
          bw = metrics.width
          row = ctx.y
          col = bx + 1
          bm = ctx.bookmark
          is_selected = (ctx.index == ctx.selected_index)
          max_width = bw - 4

          # Get chapter info
          ch_index = bm.chapter_index
          chapter = ctx.doc&.get_chapter(ch_index)
          chapter_title = chapter&.title || "Chapter #{ch_index + 1}"

          # First line: Chapter title with bookmark indicator
          if is_selected
            prefix = "#{COLOR_TEXT_ACCENT}#{SELECTION_POINTER}#{reset}"
            title_style = SELECTION_HIGHLIGHT
            snippet_style = COLOR_TEXT_SECONDARY
          else
            prefix = '  '
            title_style = COLOR_TEXT_PRIMARY
            snippet_style = COLOR_TEXT_DIM
          end
          chapter_text = chapter_title.to_s
          chapter_text = Ui::TextUtils.truncate_text(chapter_text, [max_width - 6, 1].max)

          # Modern bookmark icon
          bookmark_icon = "#{COLOR_TEXT_WARNING}◆#{reset}"
          title_line = "#{prefix}#{bookmark_icon} #{title_style}#{chapter_text}#{reset}"
          surface.write(bounds, row, col, title_line)

          # Second line: Text snippet and position
          snippet = bm.text_snippet || ''
          snippet = Ui::TextUtils.truncate_text(snippet, [max_width - 11, 1].max)

          # Add position indicator if available
          position_text = ''
          if bm.respond_to?(:position_percentage)
            pct = bm.position_percentage
            position_text = " (#{pct}%)" if pct
          end

          snippet_line = "    #{snippet_style}\"#{snippet}\"#{position_text}#{reset}"
          surface.write(bounds, row + 1, col, snippet_line)
        end

        def resolve_document
          session_context = @dependencies&.reader_session_context
          return session_context.document if session_context&.document

          @dependencies&.document
        end
      end
    end
  end
end
