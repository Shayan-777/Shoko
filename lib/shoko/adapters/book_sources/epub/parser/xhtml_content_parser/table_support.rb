# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Epub
        class XHTMLBlockBuilder
          # Shared table extraction and normalization for XHTML content blocks.
          module TableSupport
            private

            def table_blocks(element, context)
              table = parse_table(element)
              rows = table[:rows]
              return [] if rows.empty?

              lines = rows.map { |row| row[:cells].map { |cell| cell[:text] }.join(' | ') }
              inline_newline = @tag_sets[:inline_newline]
              metadata = metadata_with_quote(context, preserve_whitespace: true, table: table)
              attach_anchor_metadata(metadata, element)
              block = ContentBlock.new(
                type: :table,
                segments: [@segments.text_segment(lines.join(inline_newline), preserve_whitespace: true)],
                metadata: metadata
              )
              [block]
            end

            def parse_table(element)
              table_align = alignment_for(element)
              rows = collect_table_rows(element, table_align)
              rows = collect_direct_table_rows(element, table_align) if rows.empty?
              { rows: rows, header_rows: header_row_count(rows), align: table_align }
            end

            def collect_table_rows(element, table_align)
              element.children.each_with_object([]) do |child, rows|
                next unless child.is_a?(REXML::Element)

                append_table_rows(rows, child, table_align)
              end
            end

            def append_table_rows(rows, child, table_align)
              name = child.name.to_s.downcase
              case name
              when 'thead'
                rows.concat(parse_table_section(child, header: true, default_align: table_align))
              when 'tbody', 'tfoot'
                rows.concat(parse_table_section(child, header: false, default_align: table_align))
              when 'tr'
                rows << parse_table_row(child, header: row_has_header_cells?(child), default_align: table_align)
              end
            end

            def collect_direct_table_rows(element, table_align)
              element.each_element('tr').map do |row|
                parse_table_row(row, header: row_has_header_cells?(row), default_align: table_align)
              end
            end

            def header_row_count(rows)
              rows.take_while { |row| row[:header] }.length
            end

            def parse_table_section(section, header:, default_align:)
              rows = []
              section_align = alignment_for(section) || default_align
              section.each_element('tr') do |row|
                row_header = header || row_has_header_cells?(row)
                rows << parse_table_row(row, header: row_header, default_align: section_align)
              end
              rows
            end

            def parse_table_row(row, header:, default_align:)
              row_align = alignment_for(row) || default_align
              cells = table_cells(row, header, row_align)
              row_header = header || cells.any? { |cell| cell[:header] }
              { header: row_header, cells: cells, align: row_align }
            end

            def table_cells(row, header, row_align)
              row.elements.each_with_object([]) do |cell, acc|
                next unless table_cell?(cell)

                cell_header = header || cell.name.to_s.downcase == 'th'
                acc << table_cell_data(cell, header: cell_header, default_align: row_align)
              end
            end

            def row_has_header_cells?(row)
              row.elements.any? { |cell| table_cell?(cell) && cell.name.to_s.casecmp('th').zero? }
            end

            def table_cell_data(element, header:, default_align:)
              {
                text: table_cell_text(element),
                header: header,
                align: alignment_for(element) || default_align,
                colspan: positive_int_or_one(element.attributes['colspan']),
                rowspan: positive_int_or_one(element.attributes['rowspan']),
              }
            end

            def table_cell_text(element)
              segments = @segments.finalize_segments(@segments.collect_segments(element))
              segments.map(&:text).join
            end

            def positive_int_or_one(value)
              num = value.to_i
              num.positive? ? num : 1
            end

            def table_cell?(element)
              %w[td th].include?(element.name.to_s.downcase)
            end
          end
        end
      end
    end
  end
end
