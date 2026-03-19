# frozen_string_literal: true

require_relative '../../../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # List and status-row rendering for the annotations workspace.
          module AnnotationsScreenComponentListRenderer
            AnnotationRow = Data.define(:row, :annotation, :selected, :columns, :indent, :index)
            UI = Adapters::Ui::Constants::Ui

            private

            def render_status_row(surface, bounds, layout, count)
              scope = annotation_scope_label
              right = "#{selected + 1}/#{count} selected"
              MenuDesign::StatusRenderer.new(surface, bounds).render_status(
                row: layout[:status_row],
                indent: layout[:list_indent],
                left: truncate_text(scope, [layout[:list_render_width] - 8, 8].max),
                right: right,
                width: layout[:list_render_width],
                left_color: UI::COLOR_TEXT_DIM,
                right_color: UI::COLOR_TEXT_DIM
              )
            end

            def annotation_scope_label
              return "Book • #{build_book_label(all_mode: false)}" if @mode == :book

              'Library • All books'
            end

            def render_list(surface, bounds, layout, annotations)
              cols = layout[:list_columns]
              render_list_header(surface, bounds, layout, cols)
              annotation_rows(layout, annotations, cols).each do |row|
                render_annotation_row(surface, bounds, row)
              end
            end

            def render_list_header(surface, bounds, layout, cols)
              MenuDesign::TableRenderer.new(surface, bounds).render_header(
                row: layout[:header_row],
                indent: layout[:list_indent],
                headers: ['#', 'Ch', 'Excerpt', 'Note', 'Saved'],
                widths: [cols[:idx], cols[:chapter], cols[:excerpt], cols[:note], cols[:saved]],
                divider_char: '─'
              )
            end

            def annotation_rows(layout, annotations, cols)
              start_index, visible = Ui::ListHelpers.slice_visible(annotations, layout[:list_height], selected)
              visible.each_with_index.filter_map do |annotation, offset|
                row = layout[:list_start_row] + offset
                next if row > layout[:list_bottom_row]

                AnnotationRow.new(
                  row: row,
                  annotation: annotation,
                  selected: (start_index + offset) == selected,
                  columns: cols,
                  indent: layout[:list_indent],
                  index: start_index + offset
                )
              end
            end

            def render_annotation_row(surface, bounds, row)
              MenuDesign::TableRenderer.new(surface, bounds).render_row(
                row: row.row,
                indent: row.indent,
                cells: row_cells(row),
                widths: [row.columns[:idx], row.columns[:chapter], row.columns[:excerpt], row.columns[:note],
                         row.columns[:saved]],
                selected: row.selected
              )
            end

            def row_cells(row)
              [
                index_cell(row),
                chapter_cell(row),
                excerpt_cell_text(row),
                note_cell_text(row),
                saved_cell_text(row),
              ]
            end

            def index_cell(row)
              pad_left((row.index + 1).to_s, row.columns[:idx])
            end

            def chapter_cell(row)
              pad_right(format_chapter(row.annotation[:chapter_index]), row.columns[:chapter])
            end

            def excerpt_cell_text(row)
              text = truncate_text(excerpt_cell(row.annotation), row.columns[:excerpt])
              pad_right(text, row.columns[:excerpt])
            end

            def note_cell_text(row)
              pad_right(note_cell(row.annotation), row.columns[:note])
            end

            def saved_cell_text(row)
              pad_right(saved_cell(row.annotation), row.columns[:saved])
            end

            def excerpt_cell(annotation)
              one_line(annotation[:text], fallback: 'No selected text')
            end

            def note_cell(annotation)
              annotation[:note].to_s.strip.empty? ? '—' : 'yes'
            end

            def saved_cell(annotation)
              created_at_label(annotation[:created_at])
            end
          end
        end
      end
    end
  end
end
