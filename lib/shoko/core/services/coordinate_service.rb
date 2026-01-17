# frozen_string_literal: true

require_relative 'base_service'
require_relative '../models/selection_anchor'

module Shoko
  module Core
    module Services
      # Domain service for coordinate system management with dependency injection.
      # Migrated from legacy Services::CoordinateService to follow DI pattern.
      class CoordinateService < BaseService
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
        # geometry-based anchors or legacy screen coordinate hashes.
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

        # Calculate optimal popup position near selection end
        def calculate_popup_position(selection_end, popup_width, popup_height)
          terminal_height, terminal_width = @dependencies.resolve(:terminal_service).size

          # Start with position below selection end
          end_y = selection_end[:y]
          popup_x = selection_end[:x]
          popup_y = end_y + 1

          # Adjust if popup would go off right edge
          popup_x = [terminal_width - popup_width, 1].max if popup_x + popup_width > terminal_width

          # Adjust if popup would go off bottom edge
          if popup_y + popup_height > terminal_height
            # Try to position above selection instead
            popup_y = [end_y - popup_height, 1].max
          end

          {
            x: popup_x,
            y: popup_y,
          }
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

          {
            x: pos[:x] || pos['x'],
            y: pos[:y] || pos['y'],
          }
        end

        # Determine the column bounds (start..end) for a given click/selection position
        # by inspecting rendered geometry. Maintained for compatibility with
        # consumers that still reason about legacy coordinate ranges.
        def column_bounds_for(click_pos, rendered_lines)
          pos = normalize_position(click_pos)
          return nil unless pos

          anchor_geometry = locate_geometry(rendered_lines, pos[:x], pos[:y])
          return nil unless anchor_geometry

          start_col = anchor_geometry.column_origin
          {
            start: start_col,
            end: start_col + anchor_geometry.visible_width,
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

        protected

        def required_dependencies
          [] # No dependencies required for coordinate operations
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

          target_col = mouse_x.to_i + 1
          relative = target_col - geometry.column_origin
          relative = 0 if relative.negative?

          cells.each_with_index do |cell, index|
            cell_start = cell.screen_x
            cell_end = cell_start + cell.display_width

            if relative < cell_start
              return clamp_cell_index(index, cells.length, bias)
            elsif relative < cell_end
              return bias == :trailing ? [index + 1, cells.length].min : index
            end
          end

          return cells.length if bias == :trailing

          [cells.length - 1, 0].max
        end

        def clamp_cell_index(index, cell_count, bias)
          case bias
          when :trailing
            [[index, cell_count].min, 0].max
          when :leading
            [[index, cell_count - 1].min, 0].max
          else
            index
          end
        end

        def geometry_index_by_row(rendered_lines)
          return {} unless rendered_lines.respond_to?(:each_value)

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
      end
    end
  end
end
