# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../../adapters/output/terminal/terminal_sanitizer'
require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'

module Shoko
  module Presentation::Ui::Components
    module Screens
      # Browse screen component that renders the book browsing interface
      class BrowseScreenComponent < BaseComponent
        include Presentation::Ui::Constants::Ui
        include Ui::TextUtils

        BookItemCtx = Struct.new(:row, :book, :selected, :layout, keyword_init: true)

        def initialize(catalog_service, observer_registry, dependencies = nil)
          super()
          @catalog = catalog_service
          @observer_registry = observer_registry
          @dependencies = dependencies
          @filtered_epubs = []
          @menu_state_reader = nil
          @menu_state_writer = nil

          # Observe state changes for search and selection
          @observer_registry.add_observer(self, %i[menu browse_selected], %i[menu search_query],
                                          %i[menu search_active])
        end

        def state_changed(path, _old_value, _new_value)
          case path
          when %i[menu search_query]
            filter_books
          end
        end

        def filtered_epubs=(books)
          @filtered_epubs = apply_search_filter(books || [], menu_state_reader&.search_query)
        end

        def selected
          menu_state_reader&.browse_selected
        end

        def navigate(key)
          return unless @filtered_epubs.any?

          current = menu_state_reader&.browse_selected || 0
          max_index = @filtered_epubs.length - 1

          new_selected = case key
                         when :up then [current - 1, 0].max
                         when :down then [current + 1, max_index].min
                         else current
                         end

          menu_state_writer&.update_browse_selected(new_selected)
        end

        def selected_book
          browse_selected = menu_state_reader&.browse_selected || 0
          @filtered_epubs[browse_selected]
        end

        # Expose filtered list count for navigation logic integration
        def filtered_count
          (@filtered_epubs || []).length
        end

        # Expose random access by index (read-only)
        def book_at(index)
          (@filtered_epubs || [])[index]
        end

        def do_render(surface, bounds)
          @filtered_epubs ||= []
          layout = layout_metrics(bounds)

          render_search(surface, bounds, layout)
          render_status(surface, bounds, layout)

          if @filtered_epubs.nil? || @filtered_epubs.empty?
            render_empty_state(surface, bounds, layout)
          else
            render_books_list(surface, bounds, layout)
          end
        end

        def preferred_height(_available_height)
          :fill
        end

        private

        def filter_books
          @filtered_epubs = apply_search_filter(@catalog.entries || [], menu_state_reader&.search_query)
        end

        def apply_search_filter(books, query)
          q = query.to_s.strip.downcase
          return books if q.empty?

          books.select do |book|
            name = book['name']&.downcase
            author = book['author']&.downcase
            name&.include?(q) || author&.include?(q)
          end
        end

        def render_status(surface, bounds, layout)
          total = @filtered_epubs&.length.to_i
          status = @catalog.scan_status
          message = Shoko::Adapters::Output::Terminal::TerminalSanitizer.sanitize(@catalog.scan_message.to_s,
                                                                                  preserve_newlines: false,
                                                                                  preserve_tabs: false)
          status_row = layout[:status_row]
          indent = layout[:indent]

          count_text = "#{COLOR_TEXT_DIM}Found #{total} #{total == 1 ? 'book' : 'books'}#{Terminal::ANSI::RESET}"
          surface.write(bounds, status_row, indent, count_text)

          return unless status

          status_text = case status
                        when :scanning then "#{COLOR_TEXT_WARNING}⟳ #{message}#{Terminal::ANSI::RESET}"
                        when :error    then "#{COLOR_TEXT_ERROR}✗ #{message}#{Terminal::ANSI::RESET}"
                        when :done     then "#{COLOR_TEXT_SUCCESS}✓ #{message}#{Terminal::ANSI::RESET}"
                        else ''
                        end
          return if status_text.empty?

          offset = Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(count_text)
          surface.write(bounds, status_row, indent + offset + 2, status_text)
        end

        def render_empty_state(surface, bounds, layout)
          status = @catalog.scan_status
          empty_text = if status == :scanning
                         "#{COLOR_TEXT_WARNING}⟳ Scanning for books...#{Terminal::ANSI::RESET}"
                       else
                         "#{COLOR_TEXT_DIM}No matching books#{Terminal::ANSI::RESET}"
                       end
          row = (bounds.height / 2).clamp(layout[:list_start_row], bounds.bottom - 2)
          surface.write(bounds, row, layout[:indent], empty_text)
        end

        def render_books_list(surface, bounds, layout)
          list_start_row = layout[:list_start_row]
          list_height = bounds.height - list_start_row - 2
          return if list_height <= 0

          selected = menu_state_reader&.browse_selected || 0
          start_index, visible_books = Ui::ListHelpers.slice_visible(@filtered_epubs, list_height, selected)

          draw_list_header(surface, bounds, layout, layout[:header_row])
          current_row = list_start_row

          loading_path = menu_state_reader&.loading_path
          loading_active = menu_state_reader&.loading_active?
          loading_progress = (menu_state_reader&.loading_progress || 0.0).to_f
          loading_message = menu_state_reader&.loading_message

          visible_books.each_with_index do |book, index|
            is_selected = (start_index + index) == selected
            ctx = BookItemCtx.new(row: current_row, book: book, selected: is_selected, layout: layout)
            render_book_item(surface, bounds, ctx)

            progress_row = current_row + 1
            if loading_active && loading_path == book['path'] && progress_row <= bounds.bottom
              rows_used = draw_inline_progress(surface, bounds, layout, progress_row, loading_progress, loading_message)
              current_row += 1 + rows_used
            else
              current_row += 1
            end
          end
        end

        def render_book_item(surface, bounds, ctx)
          line = format_browse_columns(ctx.book, ctx.layout)
          content = style_browse_line(line, ctx.selected)
          surface.write(bounds, ctx.row, ctx.layout[:indent], content)
        end

        def format_browse_columns(book, layout)
          path = book['path']
          meta = @catalog.metadata_for(path)
          title = (meta[:title] || book['name'] || 'Unknown').to_s
          size_mb = format_size(book['size'] || @catalog.size_for(path))

          cols = layout[:columns]
          gap = ' ' * layout[:gap]
          [
            pad_right(truncate_text(title, cols[:title]), cols[:title]),
            pad_left(size_mb, cols[:size]),
          ].join(gap)
        end

        def style_browse_line(line, selected)
          if selected
            Terminal::ANSI::BOLD + COLOR_TEXT_ACCENT + line + Terminal::ANSI::RESET
          else
            COLOR_TEXT_PRIMARY + line + Terminal::ANSI::RESET
          end
        end

        def draw_list_header(surface, bounds, layout, row)
          return if row < 5

          indent = layout[:indent]
          content_width = layout[:content_width]
          cols = layout[:columns]
          gap = ' ' * layout[:gap]
          headers = [
            pad_right('Title', cols[:title]),
            pad_left('Size', cols[:size]),
          ].join(gap)

          header_style = Terminal::ANSI::BOLD + Terminal::ANSI::DEFAULT_FG
          padded_headers = pad_right(headers, content_width)
          surface.write(bounds, row, indent, header_style + padded_headers + Terminal::ANSI::RESET)
          # Divider line
          divider = ('─' * [content_width, 1].max)
          surface.write(bounds, row + 1, indent, COLOR_TEXT_DIM + divider + Terminal::ANSI::RESET)
        end

        def format_size(bytes)
          mb = (bytes.to_f / (1024 * 1024)).round(1)
          format('%.1f MB', mb)
        end

        def draw_inline_progress(surface, bounds, layout, row, progress, message)
          return 0 if row > bounds.bottom

          rows_used = 0
          indent = layout[:indent]
          content_width = layout[:content_width]
          message_text = message.to_s.strip

          unless message_text.empty?
            truncated = Shoko::Adapters::Output::Terminal::TextMetrics.truncate_to(message_text, content_width)
            surface.write(bounds, row, indent, "#{COLOR_TEXT_DIM}#{truncated}#{Terminal::ANSI::RESET}")
            rows_used += 1
            row += 1
            return rows_used if row > bounds.bottom
          end

          bar_col = layout[:indent]
          usable = [layout[:content_width], 10].max
          filled = (usable * progress.to_f.clamp(0.0, 1.0)).round
          accent = Terminal::ANSI::BRIGHT_GREEN
          dim = Terminal::ANSI::DIM
          reset = Terminal::ANSI::RESET
          track = accent + ('━' * filled) + reset
          track << (dim + ('━' * (usable - filled)) + reset) if filled < usable
          surface.write(bounds, row, bar_col, track)
          rows_used + 1
        end

        def render_search(surface, bounds, layout)
          row = layout[:search_row]
          indent = layout[:indent]

          surface.write(bounds, row, indent, "#{COLOR_TEXT_DIM}Search#{Terminal::ANSI::RESET}")

          search_query = menu_state_reader&.search_query || ''
          search_display = search_query.dup
          cursor_pos = menu_state_reader&.search_cursor
          cursor_pos = cursor_pos.to_i.clamp(0, search_display.length)
          search_display.insert(cursor_pos, '_')
          field_text = pad_right(search_display, layout[:content_width])

          surface.write(bounds, row + 1, indent,
                        "#{SELECTION_HIGHLIGHT}#{field_text}#{Terminal::ANSI::RESET}")
        end

        def layout_metrics(bounds)
          height = bounds.height
          width  = bounds.width
          row_base = height / 6

          base_width = [width - 8, 72].min
          column_spec = column_layout(base_width)
          content_width = column_spec[:content_width]
          indent = ((width - content_width) / 2).floor
          indent = indent.clamp(2, width / 3)

          {
            indent: indent,
            content_width: content_width,
            columns: column_spec[:columns],
            gap: column_spec[:gap],
            search_row: [row_base, 2].max,
            status_row: [row_base + 2, 4].max,
            header_row: [row_base + 4, 6].max,
            list_start_row: [row_base + 6, 8].max,
          }
        end

        def column_layout(content_width)
          gap = 4
          size_w = 8
          title_w = [content_width - size_w - gap, 24].max
          content_width = title_w + size_w + gap

          {
            content_width: content_width,
            columns: {
              title: title_w,
              size: size_w,
            },
            gap: gap,
          }
        end

        def menu_state_reader
          @menu_state_reader ||= @dependencies&.menu_state_reader
        end

        def menu_state_writer
          @menu_state_writer ||= @dependencies&.menu_state_writer
        end

        # truncate_text provided by Ui::TextUtils
      end
    end
  end
end
