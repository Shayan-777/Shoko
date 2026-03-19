# frozen_string_literal: true

require_relative '../base_component'
require_relative '../ui/list_helpers'
require_relative '../ui/text_utils'

module Shoko
  module Adapters
    module Ui
      module Components
        module Sidebar
          # Bookmarks tab renderer for sidebar
          class BookmarksTabRenderer < BaseComponent
            include Adapters::Ui::Constants::Ui

            ItemCtx = Struct.new(:bookmark, :doc, :index, :selected_index, :y)

            def initialize(dependencies)
              super()
              @dependencies = dependencies
              @reader_state_reader = nil
            end

            BoundsMetrics = Struct.new(:x, :y, :width, :height)

            def do_render(surface, bounds)
              metrics = metrics_for(bounds)
              bookmarks = reader_state_reader&.bookmarks || []
              doc = resolve_document
              selected_index = sidebar_state_reader&.sidebar_bookmarks_selected || 0

              return render_empty_message(surface, bounds, metrics) if bookmarks.empty?

              render_bookmarks_list(
                surface,
                bounds,
                metrics: metrics,
                bookmarks: bookmarks,
                doc: doc,
                selected_index: selected_index
              )
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
              render_centered_messages(
                surface,
                bounds,
                metrics,
                ['No bookmarks yet', '', 'Press "b" while reading', 'to add a bookmark']
              )
            end

            def render_bookmarks_list(surface, bounds, metrics:, bookmarks:, doc:, selected_index:)
              item_height = 2
              current_y = metrics.y
              end_y = metrics.y + metrics.height
              visible_bookmarks(bookmarks, metrics, selected_index).each do |row|
                break if current_y + item_height > end_y

                ctx = ItemCtx.new(
                  bookmark: row[:bookmark],
                  doc: doc,
                  index: row[:index],
                  selected_index: selected_index,
                  y: current_y
                )
                render_bookmark_item(surface, bounds, metrics, ctx)
                current_y += item_height
              end
            end

            def render_bookmark_item(surface, bounds, metrics, ctx)
              row = ctx.y
              col = metrics.x + 1
              max_width = metrics.width - 4
              surface.write(bounds, row, col, bookmark_title_line(ctx, max_width))
              surface.write(bounds, row + 1, col, bookmark_snippet_line(ctx, max_width))
            end

            def bookmark_position_text(bookmark)
              percentage = bookmark_percentage(bookmark)
              percentage ? " (#{percentage}%)" : ''
            end

            def render_centered_messages(surface, bounds, metrics, messages)
              reset = Shoko::Shared::Terminal::Ansi::RESET
              start_y = ((metrics.height - messages.length) / 2) + 1
              messages.each_with_index do |message, index|
                msg_width = Shoko::Shared::Terminal::TextMetrics.visible_length(message)
                col = [(metrics.width - msg_width) / 2, 2].max
                row = start_y + index
                surface.write(bounds, row, col, "#{COLOR_TEXT_DIM}#{message}#{reset}")
              end
            end

            def visible_bookmarks(bookmarks, metrics, selected_index)
              visible_items = [metrics.height / 2, 1].max
              start_index, visible = Ui::ListHelpers.slice_visible(bookmarks, visible_items, selected_index)
              visible.each_with_index.map do |bookmark, offset|
                { bookmark: bookmark, index: start_index + offset }
              end
            end

            def bookmark_title_line(ctx, max_width)
              styles = bookmark_selection_style(ctx.index == ctx.selected_index)
              chapter_text = Ui::TextUtils.truncate_text(chapter_title(ctx).to_s, [max_width - 6, 1].max)
              "#{styles[:prefix]}#{bookmark_icon} #{styles[:title]}#{chapter_text}#{styles[:reset]}"
            end

            def bookmark_snippet_line(ctx, max_width)
              snippet = Ui::TextUtils.truncate_text(ctx.bookmark.text_snippet.to_s, [max_width - 11, 1].max)
              "    #{bookmark_selection_style(ctx.index == ctx.selected_index)[:snippet]}\"#{snippet}\"" \
                "#{bookmark_position_text(ctx.bookmark)}#{Shoko::Shared::Terminal::Ansi::RESET}"
            end

            def chapter_title(ctx)
              chapter = ctx.doc&.get_chapter(ctx.bookmark.chapter_index)
              chapter&.title || "Chapter #{ctx.bookmark.chapter_index + 1}"
            end

            def bookmark_selection_style(selected)
              reset = Shoko::Shared::Terminal::Ansi::RESET
              return selected_bookmark_style(reset) if selected

              unselected_bookmark_style(reset)
            end

            def selected_bookmark_style(reset)
              {
                prefix: "#{COLOR_TEXT_ACCENT}#{SELECTION_POINTER}#{reset}",
                title: SELECTION_HIGHLIGHT,
                snippet: COLOR_TEXT_SECONDARY,
                reset: reset,
              }
            end

            def unselected_bookmark_style(reset)
              {
                prefix: '  ',
                title: COLOR_TEXT_PRIMARY,
                snippet: COLOR_TEXT_DIM,
                reset: reset,
              }
            end

            def bookmark_icon
              "#{COLOR_TEXT_WARNING}◆#{Shoko::Shared::Terminal::Ansi::RESET}"
            end

            def bookmark_percentage(bookmark)
              return bookmark[:position_percentage] if bookmark.is_a?(Hash)
              return nil unless bookmark.is_a?(Struct)
              return nil unless bookmark.members.include?(:position_percentage)

              bookmark[:position_percentage]
            end

            def resolve_document
              session_context = @dependencies&.reader_launch_state
              document = session_context&.preloaded_document
              return document if document

              @dependencies&.document
            end
          end
        end
      end
    end
  end
end
