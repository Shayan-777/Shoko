# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Formatting
        class FormattingService
          class LineAssembler
            class TableRenderer
              # Normalizes raw table metadata rows/cells into renderer-ready hashes.
              module NormalizationSupport
                private

                def normalize_rows(table_data)
                  rows = extract_rows(table_data)
                  return [] unless rows.is_a?(Array)

                  rows.map { |row| normalize_row(row) }
                end

                def extract_rows(table_data)
                  return nil unless table_data
                  return symbolize_hash(table_data)[:rows] if table_data.is_a?(Hash)

                  table_data
                end

                def normalize_row(row)
                  return normalize_hash_row(row) if row.is_a?(Hash)
                  return normalize_array_row(row) if row.is_a?(Array)

                  normalize_delimited_row(row)
                end

                def normalize_hash_row(row)
                  normalized = symbolize_hash(row)
                  row_cells = normalized[:cells] || []
                  row_header = truthy?(normalized[:header])
                  row_align = normalize_alignment(normalized[:align])
                  cells = row_cells.map { |cell| normalize_cell(cell, row_header, row_align) }
                  row_header ||= cells.any? { |cell| cell[:header] }
                  { header: row_header, cells: cells, align: row_align }
                end

                def normalize_array_row(row)
                  cells = row.map { |value| normalize_cell({ text: value }, false, nil) }
                  { header: false, cells: cells, align: nil }
                end

                def normalize_delimited_row(row)
                  cells = row.to_s.split(/\s*\|\s*/).map { |value| normalize_cell({ text: value }, false, nil) }
                  { header: false, cells: cells, align: nil }
                end

                def normalize_cell(cell, row_header, row_align)
                  return { text: '', header: row_header, colspan: 1, rowspan: 1 } unless cell
                  return normalize_hash_cell(cell, row_header, row_align) if cell.is_a?(Hash)

                  { text: cell.to_s, header: row_header, align: row_align, colspan: 1, rowspan: 1 }
                end

                def normalize_hash_cell(cell, row_header, row_align)
                  normalized = symbolize_hash(cell)
                  {
                    text: normalized[:text].to_s,
                    header: row_header || truthy?(normalized[:header]),
                    align: normalize_alignment(normalized[:align] || row_align),
                    colspan: positive_int_or_one(normalized[:colspan]),
                    rowspan: positive_int_or_one(normalized[:rowspan]),
                  }
                end

                def truthy?(value)
                  !value.nil? && value != false
                end

                def positive_int_or_one(value)
                  number = value.to_i
                  number.positive? ? number : 1
                end

                def symbolize_hash(value)
                  value.transform_keys do |key|
                    key.is_a?(String) ? key.to_sym : key
                  end
                end

                def normalize_alignment(value)
                  return value if value.is_a?(Symbol)

                  raw = value.to_s.strip.downcase
                  return nil if raw.empty?

                  normalized = raw.sub(/;+\z/, '')
                  normalized = normalized.sub(/\s*!important\z/, '').strip
                  ALIGNMENT_MAP[normalized]
                end
              end
            end
          end
        end
      end
    end
  end
end
