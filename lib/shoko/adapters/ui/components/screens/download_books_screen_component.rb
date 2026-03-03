# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../../shared/terminal/text_metrics'
require_relative '../../../../shared/terminal/text_sanitizer'
require_relative '../menu_design/frame_renderer'
require_relative '../menu_design/layout'
require_relative '../menu_design/progress_renderer'
require_relative '../menu_design/search_field_renderer'
require_relative '../menu_design/status_renderer'
require_relative '../menu_design/table_renderer'
require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Centralized download screen for Gutendex search + download flow.
          class DownloadBooksScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::TextUtils

            BookItemCtx = Struct.new(:row, :book, :selected, :layout, keyword_init: true)

            def initialize(dependencies: nil, menu_visual_profile: nil)
              super()
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
            end

            def do_render(surface, bounds)
              layout = layout_metrics(bounds)
              frame = MenuDesign::FrameRenderer.new(surface, bounds)
              frame.render_title(title: 'Download Books')
              frame.render_divider

              render_search(surface, bounds, layout)
              render_status(surface, bounds, layout)
              render_results(surface, bounds, layout)
              render_footer(surface, bounds, layout, frame: frame)
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def results
              menu_state_reader&.download_results || []
            end

            def selected_index
              (menu_state_reader&.download_selected || 0).to_i
            end

            def download_status
              (menu_state_reader&.download_status || :idle).to_sym
            end

            def download_message
              menu_state_reader&.download_message.to_s
            end

            def download_count
              (menu_state_reader&.download_count || 0).to_i
            end

            def download_progress
              (menu_state_reader&.download_progress || 0.0).to_f
            end

            def search_query
              menu_state_reader&.download_query || ''
            end

            def search_cursor
              cursor = menu_state_reader&.download_cursor
              cursor ? cursor.to_i : search_query.length
            end

            def search_active?
              menu_state_reader&.mode == :download_search
            end

            def menu_state_reader
              return @menu_state_reader if @menu_state_reader

              @menu_state_reader = @dependencies&.menu_state_reader
            end

            def render_search(surface, bounds, layout)
              MenuDesign::SearchFieldRenderer.new(surface, bounds).render(
                label: 'Search Gutendex',
                query: search_query,
                cursor: search_cursor,
                row: layout[:search_row],
                indent: layout[:indent],
                width: layout[:content_width],
                active: search_active?
              )
            end

            def render_status(surface, bounds, layout)
              row = layout[:status_row]

              shown = results.length
              total = download_count
              count_text = if total.positive? && total != shown
                             "Showing #{shown} of #{total}"
                           else
                             "Found #{shown} #{shown == 1 ? 'book' : 'books'}"
                           end

              status_text, color = status_label
              MenuDesign::StatusRenderer.new(surface, bounds).render_status(
                row: row,
                indent: layout[:indent],
                left: count_text,
                right: status_text,
                width: layout[:content_width],
                left_color: COLOR_TEXT_DIM,
                right_color: color
              )

              render_progress(surface, bounds, layout) if download_progress.positive?
            end

            def render_progress(surface, bounds, layout)
              row = layout[:progress_row]
              return if row > bounds.bottom

              MenuDesign::ProgressRenderer.new(surface, bounds).render(
                row: row,
                indent: layout[:indent],
                width: layout[:content_width],
                progress: download_progress,
                filled_char: '=',
                empty_char: '-'
              )
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
              reset = Shoko::Shared::Terminal::Ansi::RESET
              case download_status
              when :searching
                "#{COLOR_TEXT_WARNING}Searching Gutendex...#{reset}"
              when :error
                "#{COLOR_TEXT_ERROR}#{safe_text(download_message)}#{reset}"
              else
                if search_query.strip.empty?
                  "#{COLOR_TEXT_DIM}No search results yet#{reset}"
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
              start_index, visible = Ui::ListHelpers.slice_visible(items, list_height, selected)

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
              fields = extract_book_fields(ctx.book)
              cols = ctx.layout[:columns]
              cells = [
                pad_right(truncate_text(fields[:title], cols[:title]), cols[:title]),
                pad_right(truncate_text(fields[:authors], cols[:author]), cols[:author]),
                pad_right(truncate_text(fields[:languages], cols[:lang]), cols[:lang]),
                pad_left(fields[:downloads].to_s, cols[:downloads]),
              ]
              widths = [cols[:title], cols[:author], cols[:lang], cols[:downloads]]
              MenuDesign::TableRenderer.new(surface, bounds).render_row(
                row: ctx.row,
                indent: ctx.layout[:indent],
                cells: cells,
                widths: widths,
                selected: ctx.selected
              )
            end

            def extract_book_fields(book)
              {
                title: safe_text(value_for(book, :title, 'title', 'Untitled')),
                authors: safe_text(Array(value_for(book, :authors, 'authors', [])).join(', ')),
                languages: safe_text(Array(value_for(book, :languages, 'languages', [])).map(&:to_s).join(',')),
                downloads: value_for(book, :download_count, 'download_count', 0).to_i,
              }
            end

            def format_book_columns(fields, layout)
              cols = layout[:columns]
              gap = ' ' * layout[:gap]
              [
                pad_right(truncate_text(fields[:title], cols[:title]), cols[:title]),
                pad_right(truncate_text(fields[:authors], cols[:author]), cols[:author]),
                pad_right(truncate_text(fields[:languages], cols[:lang]), cols[:lang]),
                pad_left(fields[:downloads].to_s, cols[:downloads]),
              ].join(gap)
            end

            def draw_list_header(surface, bounds, layout, row)
              return if row < 5

              cols = layout[:columns]
              MenuDesign::TableRenderer.new(surface, bounds).render_header(
                row: row,
                indent: layout[:indent],
                headers: ['Title', 'Author', 'Lang', 'DLs'],
                widths: [cols[:title], cols[:author], cols[:lang], cols[:downloads]],
                divider_char: '-'
              )
            end

            def render_footer(surface, bounds, layout, frame:)
              row = layout[:footer_row]
              return if row > bounds.bottom

              clipped = Shoko::Shared::Terminal::TextMetrics.truncate_to(footer_text, layout[:content_width])
              frame.render_footer(text: clipped, row: row, indent: layout[:indent])
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
              return default unless book.is_a?(Hash)
              return book[key_sym] if book.key?(key_sym)
              return book[key_str] if book.key?(key_str)

              default
            end

            def safe_text(text)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(text.to_s, preserve_newlines: false,
                                                                         preserve_tabs: false)
            end

            def layout_metrics(bounds)
              height = bounds.height
              width = bounds.width
              row_base = height / 6

              base_width = [width - 8, 86].min
              column_spec = column_layout(base_width)
              content_width = column_spec[:content_width]
              indent = MenuDesign::Layout.centered_indent(bounds, content_width)

              header_row = 1
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

            def footer_text
              shown = results.length
              query = safe_text(search_query).strip
              return "#{shown} #{shown == 1 ? 'result' : 'results'}" if query.empty?

              "Filter: #{query}"
            end
          end
        end
      end
    end
  end
end
