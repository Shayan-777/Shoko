# frozen_string_literal: true

require_relative '../../core/models/selection_anchor'
require 'shoko/shared/hash_normalizer'

module Shoko
  module Application
    module Services
      # Application service for screen-space coordinate and selection geometry management.
      class CoordinateService
        def initialize(logger: nil)
          @logger = logger
        end

        # Convert mouse coordinates (0-based) to terminal coordinates (1-based)
        def mouse_to_terminal(mouse_x, mouse_y)
          {
            x: mouse_x + 1,
            y: mouse_y + 1,
          }
        end

        # Convert terminal coordinates (1-based) to mouse coordinates (0-based)
        def terminal_to_mouse(terminal_x, terminal_y)
          {
            x: [terminal_x - 1, 0].max,
            y: [terminal_y - 1, 0].max,
          }
        end

        # Normalize selection range ensuring start <= end. Accepts either
        # geometry-based anchors or raw screen coordinate hashes.
        #
        # @param selection_range [Hash]
        # @param rendered_lines [Hash]
        # @return [Hash,nil]
        def normalize_selection_range(selection_range, rendered_lines = nil)
          return nil unless selection_range

          start_anchor = normalize_anchor(selection_range[:start], rendered_lines)
          end_anchor = normalize_anchor(selection_range[:end], rendered_lines)
          return nil unless start_anchor && end_anchor

          start_anchor, end_anchor = end_anchor, start_anchor if (start_anchor <=> end_anchor)&.positive?

          {
            start: start_anchor.to_h,
            end: end_anchor.to_h,
          }
        end

        # Validate coordinate bounds
        def validate_coordinates?(col, row, max_col, max_row)
          col.between?(1, max_col) && row.between?(1, max_row)
        end

        # Calculate distance between two points
        def calculate_distance(x_start, y_start, x_end, y_end)
          Math.sqrt(((x_end - x_start)**2) + ((y_end - y_start)**2))
        end

        # Check if coordinates are within bounds
        def within_bounds?(col, row, bounds)
          bx = bounds.x
          by = bounds.y
          bw = bounds.width
          bh = bounds.height
          col >= bx && col < (bx + bw) && row >= by && row < (by + bh)
        end

        # Convert line-relative coordinates to absolute terminal coordinates
        def line_to_terminal(line_col, line_start_col, terminal_row)
          {
            x: line_start_col + line_col,
            y: terminal_row,
          }
        end

        # Normalize position hash to consistent format
        def normalize_position(pos)
          return nil unless pos

          normalized = normalize_keys(pos)
          {
            x: normalized[:x],
            y: normalized[:y],
          }
        end

        def column_overlaps?(line_start, line_end, bounds)
          return false unless bounds

          !(line_end < bounds[:start] || line_start > bounds[:end])
        end

        # Build an anchor from screen coordinates (0-based) using rendered geometry.
        def anchor_from_point(point, rendered_lines, bias: :nearest)
          pos = normalize_position(point)
          return nil unless pos

          geometry = locate_geometry(rendered_lines, pos[:x], pos[:y])
          return nil unless geometry

          cell_index = cell_index_for_geometry(geometry, pos[:x], bias)

          Shoko::Core::Models::SelectionAnchor.new(
            page_id: geometry.page_id,
            column_id: geometry.column_id,
            geometry_key: geometry.key,
            line_offset: geometry.line_offset,
            cell_index: cell_index,
            row: geometry.row,
            column_origin: geometry.column_origin
          )
        end

        # Convenience helper for highlight logic: find the rendered line geometry
        # that covers the provided terminal row.
        def geometry_for_row(rendered_lines, row)
          index = geometry_index_by_row(rendered_lines)
          candidates = index[row]
          candidates&.first
        end

        private

        def normalize_anchor(anchor, rendered_lines)
          return nil unless anchor

          selection_anchor = Shoko::Core::Models::SelectionAnchor.from(anchor)
          return selection_anchor if selection_anchor&.geometry_key

          return nil unless rendered_lines

          anchor_from_point(anchor, rendered_lines)
        end

        def locate_geometry(rendered_lines, mouse_x, mouse_y)
          row = mouse_y.to_i + 1
          col = mouse_x.to_i + 1

          candidates = geometry_index_by_row(rendered_lines)[row] || []
          return nil if candidates.empty?

          candidates.each do |geometry|
            line_start = geometry.column_origin
            line_end = line_start + geometry.visible_width

            if col < line_start
              return geometry if geometry.visible_width.zero?

              next
            end

            return geometry if col <= line_end || geometry.visible_width.zero?
          end

          # No direct hit; fall back to the last geometry on the row for trailing whitespace selection.
          candidates.last
        end

        def cell_index_for_geometry(geometry, mouse_x, bias)
          cells = geometry.cells
          return 0 if cells.empty?

          relative = relative_column(mouse_x, geometry)
          index = matching_cell_index(cells, relative, bias)
          return index unless index.nil?

          trailing_cell_index(cells, bias)
        end

        def clamp_cell_index(index, cell_count, bias)
          case bias
          when :trailing
            index.clamp(0, cell_count)
          when :leading
            index.clamp(0, cell_count - 1)
          else
            index
          end
        end

        def geometry_index_by_row(rendered_lines)
          return {} unless rendered_lines.is_a?(Hash)

          key = rendered_lines.object_id
          if @geometry_index_key != key
            @geometry_index_key = key
            @geometry_index_by_row = build_geometry_index(rendered_lines)
          end
          @geometry_index_by_row || {}
        end

        def build_geometry_index(rendered_lines)
          index = Hash.new { |h, k| h[k] = [] }
          rendered_lines.each_value do |line_info|
            geometry = line_info[:geometry]
            next unless geometry

            index[geometry.row] << geometry
          end
          index.each_value { |rows| rows.sort_by!(&:column_origin) }
          index
        end

        def normalize_keys(value)
          Shoko::Shared::HashNormalizer.symbolize_keys(value) || {}
        end

        def relative_column(mouse_x, geometry)
          target_col = mouse_x.to_i + 1
          relative = target_col - geometry.column_origin
          relative.negative? ? 0 : relative
        end

        def matching_cell_index(cells, relative, bias)
          cell_count = cells.length
          cells.each_with_index do |cell, index|
            return clamp_cell_index(index, cell_count, bias) if relative < cell.screen_x

            resolved = cell_index_for_relative_position(relative, cell, index, bias)
            return resolved unless resolved.nil?
          end

          nil
        end

        def cell_index_for_relative_position(relative, cell, index, bias)
          cell_end = cell.screen_x + cell.display_width
          return nil unless relative < cell_end

          bias == :trailing ? index + 1 : index
        end

        def trailing_cell_index(cells, bias)
          return cells.length if bias == :trailing

          [cells.length - 1, 0].max
        end
      end
    end
  end
end
