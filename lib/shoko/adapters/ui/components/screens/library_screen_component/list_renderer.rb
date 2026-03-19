# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # List and empty-state rendering helpers for the library screen.
          module LibraryScreenComponentListRenderer
            private

            def render_empty(surface, bounds, panel)
              row = panel.y + [panel.height / 2, 0].max
              text = "#{Adapters::Ui::Constants::Ui::COLOR_TEXT_DIM}No cached books yet" \
                     "#{Shoko::Shared::Terminal::Ansi::RESET}"
              surface.write(bounds, row, panel.x, text)
            end

            def render_library(surface, bounds, context)
              panel = context[:panel]
              render_library_header(surface, bounds, panel)

              library_rows(panel, context[:items], context[:selected]).each do |row|
                render_library_row(surface, bounds, panel, row)
              end
            end

            def render_library_header(surface, bounds, panel)
              MenuDesign::TableRenderer.new(surface, bounds).render_header(
                row: panel.y,
                indent: panel.x,
                headers: ['Title'],
                widths: [panel.width],
                divider_char: '─'
              )
            end

            def library_rows(panel, items, selected)
              visible_rows = [panel.height - 2, 0].max
              return [] if visible_rows <= 0

              start_index, visible = Ui::ListHelpers.slice_visible(items, visible_rows, selected)
              visible.each_with_index.filter_map do |book, offset|
                build_library_row(panel, book, start_index, offset, selected: selected)
              end
            end

            def build_library_row(panel, book, start_index, offset, selected:)
              row = panel.y + 2 + offset
              return nil if row > panel.bottom

              {
                row: row,
                book: book,
                index: start_index + offset,
                selected: (start_index + offset) == selected,
              }
            end

            def render_library_row(surface, bounds, panel, row)
              title = safe_text(row[:book].title || 'Untitled')
              decorated = "#{pad_left((row[:index] + 1).to_s, 3)}  #{title}"
              MenuDesign::TableRenderer.new(surface, bounds).render_row(
                row: row[:row],
                indent: panel.x,
                cells: [pad_right(truncate_text(decorated, panel.width), panel.width)],
                widths: [panel.width],
                selected: row[:selected]
              )
            end
          end
        end
      end
    end
  end
end
