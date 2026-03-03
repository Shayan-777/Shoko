# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Lightweight value object describing an anchor within rendered geometry.
      class SelectionAnchor
        ATTRIBUTES = %i[page_id column_id geometry_key line_offset cell_index row column_origin].freeze

        attr_reader(*ATTRIBUTES)

        def initialize(page_id:, column_id:, geometry_key:, line_offset:, cell_index:, row:, column_origin:)
          @page_id = page_id
          @column_id = column_id
          @geometry_key = geometry_key
          @line_offset = line_offset
          @cell_index = cell_index
          @row = row
          @column_origin = column_origin
        end

        def self.from(anchor)
          return anchor if anchor.is_a?(SelectionAnchor)
          return nil unless anchor.is_a?(Hash)

          new(
            page_id: extract(anchor, :page_id),
            column_id: extract(anchor, :column_id),
            geometry_key: extract(anchor, :geometry_key),
            line_offset: extract(anchor, :line_offset, 0),
            cell_index: extract(anchor, :cell_index, 0),
            row: extract(anchor, :row, 0),
            column_origin: extract(anchor, :column_origin, 0)
          )
        end

        def self.extract(hash, key, default = nil)
          hash[key] || hash[key.to_s] || default
        end
        private_class_method :extract

        def to_h
          {
            page_id: page_id,
            column_id: column_id,
            geometry_key: geometry_key,
            line_offset: line_offset,
            cell_index: cell_index,
            row: row,
            column_origin: column_origin,
          }
        end

        def <=>(other)
          return nil unless other.is_a?(SelectionAnchor)

          compare_tuple <=> other.compare_tuple
        end

        def compare_tuple
          [page_id || 0, line_offset, column_id || 0, row || 0, cell_index]
        end

        def with_cell_index(new_index)
          self.class.new(
            page_id: page_id,
            column_id: column_id,
            geometry_key: geometry_key,
            line_offset: line_offset,
            cell_index: new_index,
            row: row,
            column_origin: column_origin
          )
        end
      end
    end
  end
end
