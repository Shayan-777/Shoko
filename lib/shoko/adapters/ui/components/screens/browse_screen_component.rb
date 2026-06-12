# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require 'shoko/shared/terminal/text_sanitizer'
require_relative '../menu_design/master_detail_shell'
require_relative '../menu_design/progress_renderer'
require_relative '../menu_design/search_field_renderer'
require_relative '../menu_design/table_renderer'
require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Browse screen component that renders the searchable library list
          # with a persistent inspector for the selected item.
          class BrowseScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::TextUtils

            DETAIL_KEY_WIDTH = 7
            BROWSE_PREFERRED_WIDTH = 132
            UNREADABLE_METADATA = Object.new.freeze

            def initialize(catalog_service, observer_registry, dependencies = nil, menu_visual_profile: nil)
              super()
              @catalog = catalog_service
              @observer_registry = observer_registry
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @filtered_epubs = []
              @menu_state_reader = nil
              @menu_session_mutator = nil

              # Re-filter the cached book list when the search query changes;
              # selection and search-mode flags are read live on render.
              @observer_registry.add_observer(self, %i[menu search_query])
            end

            def state_changed(_path, _old_value, _new_value)
              filter_books
            end

            def filtered_epubs=(books)
              @filtered_epubs = apply_search_filter(books || [], menu_state_reader&.search_query)
            end

            def selected
              menu_state_reader&.browse_selected
            end

            def navigate(key)
              return unless @filtered_epubs.any?

              current = selected_index(@filtered_epubs.length)
              max_index = @filtered_epubs.length - 1
              new_selected = case key
                             when :up then [current - 1, 0].max
                             when :down then [current + 1, max_index].min
                             else current
                             end
              menu_session_mutator&.update_menu(browse_selected: new_selected)
            end

            def selected_book
              @filtered_epubs[selected_index(@filtered_epubs.length)]
            end

            def filtered_count
              @filtered_epubs.length
            end

            def book_at(index)
              @filtered_epubs[index]
            end

            def do_render(surface, bounds)
              @filtered_epubs ||= []
              shell = MenuDesign::MasterDetailShell.new(surface, bounds)
              layout = build_shell_layout(shell)
              summary = summary_context

              render_shell_frame(shell, layout, summary)
              render_search(surface, bounds, layout)
              shell.render_panels(layout: layout, primary_title: 'Results', secondary_title: 'Selection')

              if @filtered_epubs.empty?
                render_empty_results(surface, bounds, layout.primary_panel.content)
              else
                render_books_list(surface, bounds, layout.primary_panel.content)
              end

              render_selection_details(surface, bounds, layout.secondary_panel&.content)
            end

            def preferred_height(_available_height)
              :fill
            end

            UI = Adapters::Ui::Constants::Ui

            BookRow = Data.define(:row, :book, :selected, :columns, :indent)

            private

            def build_shell_layout(shell)
              shell.build_layout(
                prelude_rows: 1,
                detail_visible: true,
                desired_detail_width: 40,
                min_primary_width: 38,
                min_detail_width: 30,
                stacked_detail_height: 8,
                preferred_width: BROWSE_PREFERRED_WIDTH
              )
            end

            def summary_context
              count_text, status_text, status_color = summary_payload
              { count_text: count_text, status_text: status_text, status_color: status_color }
            end

            def render_shell_frame(shell, layout, summary)
              shell.render_frame(
                layout: layout,
                title: 'Browse Library',
                hint: 'ENTER open  / search  ESC back',
                summary_left: summary[:count_text],
                summary_right: summary[:status_text],
                footer: footer_text,
                summary_right_color: summary[:status_color]
              )
            end

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

            def summary_payload
              total = @filtered_epubs.length
              count_text = "Found #{total} #{total == 1 ? 'book' : 'books'}"
              status = @catalog.scan_status
              message = sanitize_text(@catalog.scan_message)
              case status
              when :scanning
                [count_text, message.empty? ? 'Scanning library' : "Scanning: #{message}", COLOR_TEXT_WARNING]
              when :error
                [count_text, message.empty? ? 'Scan failed' : message, COLOR_TEXT_ERROR]
              when :done
                [count_text, message.empty? ? 'Library ready' : message, COLOR_TEXT_DIM]
              else
                [count_text, '', COLOR_TEXT_DIM]
              end
            end

            def render_search(surface, bounds, layout)
              MenuDesign::SearchFieldRenderer.new(surface, bounds).render(
                label: 'Search',
                query: menu_state_reader&.search_query || '',
                cursor: menu_state_reader&.search_cursor,
                row: layout.prelude_top,
                indent: layout.shell_indent,
                width: layout.shell_width,
                active: menu_state_reader&.search_active? == true,
                compact: true
              )
            end

            def render_empty_results(surface, bounds, panel)
              status = @catalog.scan_status
              message = status == :scanning ? 'Scanning for books...' : 'No matching books'
              row = panel.y + [panel.height / 2, 0].max
              surface.write(bounds, row, panel.x, "#{COLOR_TEXT_DIM}#{message}#{Shoko::Shared::Terminal::Ansi::RESET}")
            end

            def display_author(meta, book)
              normalize_author(meta_value(meta, :author) || meta_value(meta, :authors) || book['author'])
            end

            def safe_metadata_for(book)
              @catalog.display_metadata_for(
                book['path'],
                size: book['size'],
                modified: book['modified']
              )
            rescue Shoko::MalformedMetadataInputError
              UNREADABLE_METADATA
            end

            def meta_value(meta, key)
              return nil unless meta.is_a?(Hash)

              meta[key]
            end

            def normalize_author(value)
              if value.is_a?(Array)
                names = value.filter_map do |item|
                  sanitized = sanitize_text(item)
                  sanitized unless sanitized.empty?
                end
                names.join(', ')
              else
                sanitize_text(value)
              end
            end

            def display_title(meta_title:, fallback_name:)
              raw = meta_title || fallback_name || 'Unknown'
              sanitized = sanitize_text(raw)
              sanitized.empty? ? 'Unknown' : sanitized
            end

            def sanitize_text(value)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(
                value.to_s,
                preserve_newlines: false,
                preserve_tabs: false
              ).strip
            end

            def selected_index(total)
              return 0 if total <= 0

              current = (menu_state_reader&.browse_selected || 0).to_i
              current.clamp(0, total - 1)
            end

            def footer_text
              query = sanitize_text(menu_state_reader&.search_query)
              query.empty? ? nil : "Filter: #{query}"
            end

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
            end

            def menu_session_mutator
              @menu_session_mutator ||= @dependencies&.menu_session_mutator
            end

            def render_selection_details(surface, bounds, panel)
              return unless panel

              book = selected_book
              return render_empty_selection(surface, bounds, panel) unless book

              context = { surface: surface, bounds: bounds, panel: panel }
              detail = selected_book_detail(panel, book)
              row = write_detail_title(context, detail)
              row = write_detail_author(context, detail, row)
              write_detail_lines(context, detail[:lines], row)
            end

            def render_empty_selection(surface, bounds, panel)
              surface.write(bounds,
                            panel.y,
                            panel.x,
                            "#{UI::COLOR_TEXT_DIM}No book selected#{Shoko::Shared::Terminal::Ansi::RESET}")
            end

            def selected_book_detail(panel, book)
              meta = safe_metadata_for(book)
              {
                title: display_title(meta_title: meta_value(meta, :title), fallback_name: book['name']),
                author: display_author(meta, book),
                lines: detail_lines(book, panel.width),
              }
            end

            def write_detail_title(context, detail)
              title_style = "#{Shoko::Shared::Terminal::Ansi::BOLD}#{UI::COLOR_TEXT_ACCENT}"
              write_wrapped_detail(context, context[:panel].y, detail[:title], style: title_style)
            end

            def write_detail_author(context, detail, row)
              panel = context[:panel]
              return row + 1 if detail[:author].empty? || row > panel.bottom

              context[:surface].write(context[:bounds],
                                      row,
                                      panel.x,
                                      "#{UI::COLOR_TEXT_DIM}#{detail[:author]}#{Shoko::Shared::Terminal::Ansi::RESET}")
              row + 2
            end

            def write_detail_lines(context, lines, start_row)
              panel = context[:panel]
              row = start_row
              lines.each do |line|
                break if row > panel.bottom

                context[:surface].write(context[:bounds],
                                        row,
                                        panel.x,
                                        "#{UI::COLOR_TEXT_PRIMARY}#{line}#{Shoko::Shared::Terminal::Ansi::RESET}")
                row += 1
              end
            end

            def write_wrapped_detail(context, row, text, style:)
              panel = context[:panel]
              wrap_text(text, panel.width).each do |line|
                break if row > panel.bottom

                context[:surface].write(context[:bounds],
                                        row,
                                        panel.x,
                                        "#{style}#{line}#{Shoko::Shared::Terminal::Ansi::RESET}")
                row += 1
              end
              row
            end

            def detail_lines(book, width)
              lines = []
              append_detail(lines, 'Size', format_size(book['size'] || @catalog.size_for(book['path'])), width)
              append_detail(lines, 'Format', file_format(book['path']), width)
              append_detail(lines, 'File', File.basename(book['path'].to_s), width)
              lines << ''
              lines << "#{UI::COLOR_TEXT_DIM}Enter opens the selected book#{Shoko::Shared::Terminal::Ansi::RESET}"
              lines
            end

            def append_detail(lines, label, value, width)
              safe_value = sanitize_text(value)
              safe_value = '—' if safe_value.empty?
              value_width = [width - BrowseScreenComponent::DETAIL_KEY_WIDTH - 1, 8].max
              wrap_text(safe_value, value_width).each_with_index do |part, index|
                key = if index.zero?
                        pad_right("#{label}:", BrowseScreenComponent::DETAIL_KEY_WIDTH)
                      else
                        ' ' * BrowseScreenComponent::DETAIL_KEY_WIDTH
                      end
                lines << "#{key}#{truncate_text(part, value_width)}"
              end
            end

            def file_format(path)
              extension = File.extname(path.to_s).delete('.').upcase
              extension.empty? ? 'BOOK' : extension
            end

            def render_books_list(surface, bounds, panel)
              columns = column_layout(panel.width)
              render_books_header(surface, bounds, panel, columns)
              render_visible_books(surface, bounds, panel, columns)
            end

            def render_books_header(surface, bounds, panel, columns)
              MenuDesign::TableRenderer.new(surface, bounds).render_header(
                row: panel.y,
                indent: panel.x,
                headers: %w[Title Size],
                widths: [columns[:title], columns[:size]],
                divider_char: '─'
              )
            end

            def render_visible_books(surface, bounds, panel, columns)
              start_index, visible_books, selected = visible_books_slice(panel)
              return unless visible_books

              render_visible_book_rows(surface:, bounds:, panel:, columns:, start_index:, selected:, visible_books:)
            end

            def render_visible_book(surface:, bounds:, panel:, columns:, book:, absolute_index:, selected:,
                                    current_row:)
              return panel.bottom + 1 if current_row > panel.bottom

              render_book_item(
                surface,
                bounds,
                build_book_row(
                  book: book,
                  columns: columns,
                  indent: panel.x,
                  row: current_row,
                  absolute_index: absolute_index,
                  selected: selected
                )
              )
              advance_book_row(surface: surface, bounds: bounds, panel: panel, book: book, current_row: current_row)
            end

            def build_book_row(book:, columns:, indent:, row:, absolute_index:, selected:)
              BookRow.new(
                row: row,
                book: book,
                selected: absolute_index == selected,
                columns: columns,
                indent: indent
              )
            end

            def render_book_item(surface, bounds, row)
              MenuDesign::TableRenderer.new(surface, bounds).render_row(
                row: row.row,
                indent: row.indent,
                cells: book_row_cells(row),
                widths: [row.columns[:title], row.columns[:size]],
                selected: row.selected
              )
            end

            def book_row_cells(row)
              path = row.book['path']
              [
                pad_right(truncate_text(book_title(row.book), row.columns[:title]), row.columns[:title]),
                pad_left(book_size_label(row.book, path), row.columns[:size]),
              ]
            end

            def book_title(book)
              meta = safe_metadata_for(book)
              display_title(meta_title: meta_value(meta, :title), fallback_name: book['name'])
            end

            def book_size_label(book, path)
              format_size(book['size'] || @catalog.size_for(path))
            end

            def advance_book_row(surface:, bounds:, panel:, book:, current_row:)
              progress_row = current_row + 1
              return current_row + 1 unless loading_for?(book) && progress_row <= panel.bottom

              current_row + 1 + draw_inline_progress(progress_context(surface, bounds, panel, progress_row))
            end

            def visible_books_slice(panel)
              visible_rows = [panel.height - 2 - loading_progress_reserve, 0].max
              return [nil, nil, nil] if visible_rows <= 0

              selected = selected_index(@filtered_epubs.length)
              start_index, visible_books = Ui::ListHelpers.slice_visible(@filtered_epubs, visible_rows, selected)
              [start_index, visible_books, selected]
            end

            # Rows the inline loading indicator needs below the loading book (the progress bar, plus a
            # message row when one is present). While a book is loading it is the selected book, which
            # the visible window pins to the bottom row — leaving no room beneath it. Reserving those
            # rows scrolls the book up just enough to keep its indicator on-screen instead of clipped.
            def loading_progress_reserve
              return 0 unless menu_state_reader&.loading_active?

              loading_message.strip.empty? ? 1 : 2
            end

            def render_visible_book_rows(surface:, bounds:, panel:, columns:, start_index:, selected:, visible_books:)
              current_row = panel.y + 2
              visible_books.each_with_index do |book, offset|
                current_row = render_visible_book(surface: surface,
                                                  bounds: bounds,
                                                  panel: panel,
                                                  columns: columns,
                                                  book: book,
                                                  absolute_index: start_index + offset,
                                                  selected: selected,
                                                  current_row: current_row)
                break if current_row > panel.bottom
              end
            end

            def progress_context(surface, bounds, panel, row)
              {
                surface: surface,
                bounds: bounds,
                panel: panel,
                row: row,
                progress: loading_progress,
                message: loading_message,
              }
            end

            def draw_inline_progress(context)
              return 0 if context[:row] > context[:panel].bottom

              rows_used = render_progress_message(context)
              return rows_used if next_progress_row(context, rows_used) > context[:panel].bottom

              render_progress_bar(context, next_progress_row(context, rows_used))
              rows_used + 1
            end

            def render_progress_message(context)
              message_text = sanitize_text(context[:message])
              return 0 if message_text.empty?

              truncated = Shoko::Shared::Terminal::TextMetrics.truncate_to(message_text, context[:panel].width)
              context[:surface].write(
                context[:bounds],
                context[:row],
                context[:panel].x,
                "#{UI::COLOR_TEXT_DIM}#{truncated}#{Shoko::Shared::Terminal::Ansi::RESET}"
              )
              1
            end

            def next_progress_row(context, rows_used)
              context[:row] + rows_used
            end

            def render_progress_bar(context, row)
              MenuDesign::ProgressRenderer.new(context[:surface], context[:bounds]).render(
                row: row,
                indent: context[:panel].x,
                width: context[:panel].width,
                progress: context[:progress],
                filled_char: '━',
                empty_char: '━'
              )
            end

            def column_layout(content_width)
              gap = 3
              size_width = 9
              { title: [content_width - size_width - gap, 16].max, size: size_width }
            end

            def format_size(bytes)
              mb = (bytes.to_f / (1024 * 1024)).round(1)
              format('%.1f MB', mb)
            end

            def loading_for?(book)
              menu_state_reader&.loading_active? && menu_state_reader&.loading_path == book['path']
            end

            def loading_progress
              (menu_state_reader&.loading_progress || 0.0).to_f
            end

            def loading_message
              menu_state_reader&.loading_message.to_s
            end
          end
        end
      end
    end
  end
end
