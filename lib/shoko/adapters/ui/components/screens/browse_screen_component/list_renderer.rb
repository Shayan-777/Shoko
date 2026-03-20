# frozen_string_literal: true

require_relative '../../../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Results-list rendering and inline loading progress for browse screen.
          module BrowseScreenComponentListRenderer
            UI = Adapters::Ui::Constants::Ui
            BookRow = Data.define(:row, :book, :selected, :columns, :indent)

            private

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
                pad_right(truncate_text(book_title(row.book, path), row.columns[:title]), row.columns[:title]),
                pad_left(book_size_label(row.book, path), row.columns[:size]),
              ]
            end

            def book_title(book, path)
              meta = safe_metadata_for(path)
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
              visible_rows = [panel.height - 2, 0].max
              return [nil, nil, nil] if visible_rows <= 0

              selected = selected_index(@filtered_epubs.length)
              start_index, visible_books = Ui::ListHelpers.slice_visible(@filtered_epubs, visible_rows, selected)
              [start_index, visible_books, selected]
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
