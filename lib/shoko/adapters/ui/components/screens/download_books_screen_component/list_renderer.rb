# frozen_string_literal: true

require_relative '../../../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Rendering helpers for the download source selector and results list.
          module DownloadBooksScreenComponentListRenderer
            UI = Adapters::Ui::Constants::Ui

            private

            def render_search(surface, bounds, layout)
              MenuDesign::SearchFieldRenderer.new(surface, bounds).render(
                label: "Search #{current_source_label}",
                query: search_query,
                cursor: search_cursor,
                row: layout[:search_row],
                indent: layout[:indent],
                width: layout[:content_width],
                active: search_active?
              )
            end

            def render_source(surface, bounds, layout)
              reset = Shoko::Shared::Terminal::Ansi::RESET
              label = "#{UI::COLOR_TEXT_DIM}Source#{reset}"
              value = button_string(current_source_label, active: true)
              surface.write(bounds, layout[:source_row], layout[:indent], "#{label}  #{value}")
              return unless source_selection_active?

              render_source_options(surface, bounds, layout, reset)
            end

            def render_source_options(surface, bounds, layout, reset)
              row = layout[:source_options_row]
              source_options.each_with_index do |source, index|
                surface.write(bounds, row + index, layout[:indent] + 2, source_option_text(source, index, reset))
              end
            end

            def source_option_text(source, index, reset)
              selected = index == selected_source_index
              active = source == current_source
              prefix = if selected
                         "#{Shoko::Shared::Terminal::Ansi::BOLD}#{UI::MENU_SELECTION_BG}#{UI::MENU_SELECTION_TEXT}"
                       else
                         UI::COLOR_TEXT_PRIMARY
                       end
              marker = active ? '[x]' : '[ ]'
              "#{prefix} #{marker} #{Shoko::Shared::DownloadSourcePolicy.label_for(source)} #{reset}"
            end

            def render_status(surface, bounds, layout)
              MenuDesign::StatusRenderer.new(surface, bounds).render_status(
                row: layout[:status_row],
                indent: layout[:indent],
                left: result_count_text,
                right: status_label.first,
                width: layout[:content_width],
                left_color: UI::COLOR_TEXT_DIM,
                right_color: status_label.last
              )
              render_progress(surface, bounds, layout) if download_progress.positive?
            end

            def result_count_text
              shown = results.length
              total = download_count
              return "Showing #{shown} of #{total}" if total.positive? && total != shown

              "Found #{shown} #{shown == 1 ? 'book' : 'books'}"
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
              return render_empty_state(surface, bounds, layout) if results.empty?

              render_results_list(surface, bounds, layout, results)
            end

            def render_empty_state(surface, bounds, layout)
              row = (bounds.height / 2).clamp(layout[:list_start_row], bounds.bottom - 2)
              surface.write(bounds, row, layout[:indent], empty_state_message)
            end

            def render_results_list(surface, bounds, layout, items)
              list_height = bounds.height - layout[:list_start_row] - 3
              return if list_height <= 0

              draw_list_header(surface, bounds, layout, layout[:header_row_list])
              visible_book_rows(items, list_height, layout).each do |row|
                render_book_item(surface, bounds, row)
              end
            end

            def visible_book_rows(items, list_height, layout)
              start_index, visible = Ui::ListHelpers.slice_visible(items, list_height, selected_index)
              visible.each_with_index.filter_map do |book, offset|
                build_book_row(layout, book, start_index, offset)
              end
            end

            def build_book_row(layout, book, start_index, offset)
              row = layout[:list_start_row] + offset
              return nil if row > layout[:footer_row] - 1

              DownloadBooksScreenComponent::BookItemCtx.new(
                row: row,
                book: book,
                selected: (start_index + offset) == selected_index,
                layout: layout
              )
            end

            def render_book_item(surface, bounds, ctx)
              cols = ctx.layout[:columns]
              MenuDesign::TableRenderer.new(surface, bounds).render_row(
                row: ctx.row,
                indent: ctx.layout[:indent],
                cells: book_row_cells(ctx.book, cols),
                widths: [cols[:title], cols[:author], cols[:lang], cols[:meta]],
                selected: ctx.selected
              )
            end

            def book_row_cells(book, cols)
              fields = extract_book_fields(book)
              [
                padded_book_cell(fields[:title], cols[:title]),
                padded_book_cell(fields[:authors], cols[:author]),
                padded_book_cell(fields[:languages], cols[:lang]),
                pad_left(fields[:meta].to_s, cols[:meta]),
              ]
            end

            def padded_book_cell(text, width)
              pad_right(truncate_text(text, width), width)
            end

            def render_footer(_surface, bounds, layout, frame:)
              row = layout[:footer_row]
              return if row > bounds.bottom

              clipped = Shoko::Shared::Terminal::TextMetrics.truncate_to(footer_text, layout[:content_width])
              frame.render_footer(text: clipped, row: row, indent: layout[:indent])
            end
          end
        end
      end
    end
  end
end
