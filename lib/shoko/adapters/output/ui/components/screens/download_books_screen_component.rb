# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../terminal/text_metrics.rb'
require_relative '../../../terminal/terminal_sanitizer.rb'
require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'

module Shoko
  module Adapters::Output::Ui::Components
    module Screens
      # Centralized download screen for Gutendex search + download flow.
      class DownloadBooksScreenComponent < BaseComponent
        include Adapters::Output::Ui::Constants::UI
        include UI::TextUtils

        BookItemCtx = Struct.new(:row, :book, :selected, :layout, keyword_init: true)

        def initialize(state)
          super()
          @state = state
        end

        def do_render(surface, bounds)
          layout = layout_metrics(bounds)

          render_header(surface, bounds, layout)
          render_search(surface, bounds, layout)
          render_status(surface, bounds, layout)
          render_results(surface, bounds, layout)
          render_footer(surface, bounds, layout)
        end

        def preferred_height(_available_height)
          :fill
        end

        private

        def results
          Array(@state.get(%i[menu download_results]))
        end

        def selected_index
          (@state.get(%i[menu download_selected]) || 0).to_i
        end

        def download_status
          (@state.get(%i[menu download_status]) || :idle).to_sym
        end

        def download_message
          @state.get(%i[menu download_message]).to_s
        end

        def download_count
          (@state.get(%i[menu download_count]) || 0).to_i
        end

        def download_progress
          (@state.get(%i[menu download_progress]) || 0.0).to_f
        end

        def search_query
          @state.get(%i[menu download_query]) || ''
        end

        def search_cursor
          cursor = @state.get(%i[menu download_cursor])
          cursor ? cursor.to_i : search_query.length
        end

        def search_active?
          @state.get(%i[menu mode]) == :download_search
        end

        def render_header(surface, bounds, layout)
          title_plain = 'Download Books'
          reset = Terminal::ANSI::RESET
          surface.write(bounds, layout[:header_row], layout[:indent],
                        "#{COLOR_TEXT_ACCENT}#{title_plain}#{reset}")
        end

        def render_search(surface, bounds, layout)
          row = layout[:search_row]
          indent = layout[:indent]
          reset = Terminal::ANSI::RESET

          surface.write(bounds, row, indent, "#{COLOR_TEXT_DIM}Search Gutendex#{reset}")

          query = search_query.dup
          cursor = search_cursor.clamp(0, query.length)
          query.insert(cursor, '_')
          field_text = pad_right(query, layout[:content_width])

          style = search_active? ? SELECTION_HIGHLIGHT : COLOR_TEXT_DIM
          surface.write(bounds, row + 1, indent, "#{style}#{field_text}#{reset}")
        end

        def render_status(surface, bounds, layout)
          row = layout[:status_row]
          indent = layout[:indent]
          reset = Terminal::ANSI::RESET

          shown = results.length
          total = download_count
          count_text = if total.positive? && total != shown
                         "#{COLOR_TEXT_DIM}Showing #{shown} of #{total}#{reset}"
                       else
                         "#{COLOR_TEXT_DIM}Found #{shown} #{shown == 1 ? 'book' : 'books'}#{reset}"
                       end
          surface.write(bounds, row, indent, count_text)

          status_text, color = status_label
          return if status_text.empty?

          offset = Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(count_text)
          surface.write(bounds, row, indent + offset + 2, "#{color}#{status_text}#{reset}")

          render_progress(surface, bounds, layout) if download_progress.positive?
        end

        def render_progress(surface, bounds, layout)
          row = layout[:progress_row]
          return if row > bounds.bottom

          indent = layout[:indent]
          content_width = layout[:content_width]
          usable = [content_width, 10].max
          filled = (usable * download_progress.clamp(0.0, 1.0)).round

          accent = Terminal::ANSI::BRIGHT_GREEN
          dim = Terminal::ANSI::DIM
          reset = Terminal::ANSI::RESET
          track = accent + ('=' * filled) + reset
          track << (dim + ('-' * (usable - filled)) + reset) if filled < usable
          surface.write(bounds, row, indent, track)
        end

        def render_results(surface, bounds, layout)
          items = results
          if items.empty?
            render_empty_state(surface, bounds, layout)
          else
            render_results_list(surface, bounds, layout, items)
          end
        end

        def render_empty_state(surface, bounds, layout)
          row = (bounds.height / 2).clamp(layout[:list_start_row], bounds.bottom - 2)
          message = empty_state_message
          surface.write(bounds, row, layout[:indent], message)
        end

        def empty_state_message
          reset = Terminal::ANSI::RESET
          case download_status
          when :searching
            "#{COLOR_TEXT_WARNING}Searching Gutendex...#{reset}"
          when :error
            "#{COLOR_TEXT_ERROR}#{safe_text(download_message)}#{reset}"
          else
            if search_query.strip.empty?
              "#{COLOR_TEXT_DIM}Type to search and press Enter#{reset}"
            else
              "#{COLOR_TEXT_DIM}No results for your search#{reset}"
            end
          end
        end

        def render_results_list(surface, bounds, layout, items)
          list_start_row = layout[:list_start_row]
          list_height = bounds.height - list_start_row - 3
          return if list_height <= 0

          selected = selected_index
          start_index, visible = UI::ListHelpers.slice_visible(items, list_height, selected)

          draw_list_header(surface, bounds, layout, layout[:header_row_list])

          current_row = list_start_row
          visible.each_with_index do |book, index|
            is_selected = (start_index + index) == selected
            ctx = BookItemCtx.new(row: current_row, book: book, selected: is_selected, layout: layout)
            render_book_item(surface, bounds, ctx)
            current_row += 1
            break if current_row > bounds.bottom
          end
        end

        def render_book_item(surface, bounds, ctx)
          book = ctx.book
          layout = ctx.layout
          cols = layout[:columns]
          gap = ' ' * layout[:gap]

          title = safe_text(value_for(book, :title, 'title', 'Untitled'))
          authors = Array(value_for(book, :authors, 'authors', [])).join(', ')
          authors = safe_text(authors)
          languages = Array(value_for(book, :languages, 'languages', [])).map(&:to_s).join(',')
          languages = safe_text(languages)
          downloads = value_for(book, :download_count, 'download_count', 0).to_i

          title_col = pad_right(truncate_text(title, cols[:title]), cols[:title])
          author_col = pad_right(truncate_text(authors, cols[:author]), cols[:author])
          lang_col = pad_right(truncate_text(languages, cols[:lang]), cols[:lang])
          dl_col = pad_left(downloads.to_s, cols[:downloads])

          line = [title_col, author_col, lang_col, dl_col].join(gap)

          content = if ctx.selected
                      Terminal::ANSI::BOLD + COLOR_TEXT_ACCENT + line + Terminal::ANSI::RESET
                    else
                      COLOR_TEXT_PRIMARY + line + Terminal::ANSI::RESET
                    end
          surface.write(bounds, ctx.row, layout[:indent], content)
        end

        def draw_list_header(surface, bounds, layout, row)
          return if row < 5

          indent = layout[:indent]
          content_width = layout[:content_width]
          cols = layout[:columns]
          gap = ' ' * layout[:gap]

          headers = [
            pad_right('Title', cols[:title]),
            pad_right('Author', cols[:author]),
            pad_right('Lang', cols[:lang]),
            pad_left('DLs', cols[:downloads]),
          ].join(gap)

          header_style = Terminal::ANSI::BOLD + Terminal::ANSI::DEFAULT_FG
          padded = pad_right(headers, content_width)
          surface.write(bounds, row, indent, header_style + padded + Terminal::ANSI::RESET)
          divider = ('-' * [content_width, 1].max)
          surface.write(bounds, row + 1, indent, COLOR_TEXT_DIM + divider + Terminal::ANSI::RESET)
        end

        def render_footer(surface, bounds, layout)
          row = layout[:footer_row]
          return if row > bounds.bottom

          reset = Terminal::ANSI::RESET
          hint = if search_active?
                   '[Enter] Search  [/ or ESC] Back'
                 else
                   '[Enter] Download  [/] Search  [N/P] Page  [ESC] Back'
                 end
          clipped = Shoko::Adapters::Output::Terminal::TextMetrics.truncate_to(hint, layout[:content_width])
          surface.write(bounds, row, layout[:indent], "#{COLOR_TEXT_DIM}#{clipped}#{reset}")
        end

        def status_label
          msg = safe_text(download_message)
          case download_status
          when :searching
            [msg.empty? ? 'Searching...' : msg, COLOR_TEXT_WARNING]
          when :downloading
            [msg.empty? ? 'Downloading...' : msg, COLOR_TEXT_WARNING]
          when :error
            [msg.empty? ? 'Request failed' : msg, COLOR_TEXT_ERROR]
          when :done
            [msg, COLOR_TEXT_SUCCESS]
          else
            ['', COLOR_TEXT_DIM]
          end
        end

        def value_for(book, key_sym, key_str, default)
          return book[key_sym] if book.respond_to?(:key?) && book.key?(key_sym)
          return book[key_str] if book.respond_to?(:key?) && book.key?(key_str)

          default
        end

        def safe_text(text)
          Shoko::Adapters::Output::Terminal::TerminalSanitizer.sanitize(text.to_s, preserve_newlines: false,
                                                                      preserve_tabs: false)
        end

        def layout_metrics(bounds)
          height = bounds.height
          width = bounds.width
          row_base = height / 6

          base_width = [width - 8, 86].min
          column_spec = column_layout(base_width)
          content_width = column_spec[:content_width]
          indent = ((width - content_width) / 2).floor
          indent = indent.clamp(2, width / 3)

          header_row = [row_base - 2, 1].max
          search_row = [row_base, header_row + 2].max
          status_row = search_row + 2
          progress_row = status_row + 1
          header_row_list = status_row + 2
          list_start_row = header_row_list + 2
          footer_row = [height - 2, list_start_row + 2].max

          {
            indent: indent,
            content_width: content_width,
            columns: column_spec[:columns],
            gap: column_spec[:gap],
            header_row: header_row,
            search_row: search_row,
            status_row: status_row,
            progress_row: progress_row,
            header_row_list: header_row_list,
            list_start_row: list_start_row,
            footer_row: footer_row,
          }
        end

        def column_layout(content_width)
          gap = 3
          downloads_w = 6
          lang_w = 6
          author_w = 18
          title_w = [content_width - (downloads_w + lang_w + author_w + (gap * 3)), 16].max
          content_width = title_w + author_w + lang_w + downloads_w + (gap * 3)

          {
            content_width: content_width,
            columns: {
              title: title_w,
              author: author_w,
              lang: lang_w,
              downloads: downloads_w,
            },
            gap: gap,
          }
        end
      end
    end
  end
end
