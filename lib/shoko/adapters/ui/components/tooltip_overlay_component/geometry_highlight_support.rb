# frozen_string_literal: true

require_relative '../base_component'

module Shoko
  module Adapters
    module Ui
      module Components
        class TooltipOverlayComponent < BaseComponent
          # Shared geometry-to-screen highlight rendering for selections and search hits.
          module GeometryHighlightSupport
            UI = Adapters::Ui::Constants::Ui

            private

            def render_text_highlight(surface, bounds, range, color)
              rendered_lines = rendered_content_reader&.rendered_lines || {}
              return if rendered_lines.empty?

              anchors = normalized_highlight_anchors(range, rendered_lines)
              return unless anchors

              render_geometry_range(surface: surface,
                                    bounds: bounds,
                                    rendered_lines: rendered_lines,
                                    color: color,
                                    **anchors)
            end

            def normalized_highlight_anchors(range, rendered_lines)
              normalized_range = @coordinate_service.normalize_selection_range(range, rendered_lines)
              return nil unless normalized_range

              start_anchor = Shoko::Core::Models::SelectionAnchor.from(normalized_range[:start])
              end_anchor = Shoko::Core::Models::SelectionAnchor.from(normalized_range[:end])
              return nil unless start_anchor && end_anchor

              { start_anchor: start_anchor, end_anchor: end_anchor }
            end

            def render_geometry_range(surface:, bounds:, rendered_lines:, color:, start_anchor:, end_anchor:)
              cache = geometry_cache_for(rendered_lines)
              geometries = highlight_geometries(cache, start_anchor, end_anchor)
              return unless geometries

              geometries.each do |geometry|
                render_geometry_highlight(
                  surface: surface,
                  bounds: bounds,
                  geometry: geometry,
                  start_cell: highlight_start_cell(geometry, start_anchor),
                  end_cell: highlight_end_cell(geometry, end_anchor),
                  color: color
                )
              end
            end

            def highlight_geometries(cache, start_anchor, end_anchor)
              ordered = cache[:ordered]
              return nil if ordered.empty?

              start_idx = cache[:index_by_key][start_anchor.geometry_key]
              end_idx = cache[:index_by_key][end_anchor.geometry_key]
              return nil unless start_idx && end_idx

              ordered[start_idx..end_idx]
            end

            def highlight_start_cell(geometry, start_anchor)
              geometry.key == start_anchor.geometry_key ? start_anchor.cell_index : 0
            end

            def highlight_end_cell(geometry, end_anchor)
              geometry.key == end_anchor.geometry_key ? end_anchor.cell_index : geometry.cells.length
            end

            def render_geometry_highlight(surface:, bounds:, geometry:, start_cell:, end_cell:, color:,
                                          foreground: UI::COLOR_TEXT_PRIMARY, tracker: :selection)
              return if end_cell <= start_cell

              start_char = char_index_for_cell(geometry, start_cell)
              end_char = char_index_for_cell(geometry, end_cell)
              segment_text = highlighted_text_segment(geometry, start_char, end_char)
              return if segment_text.empty?

              highlight = "#{color}#{foreground}#{segment_text}#{Shoko::Shared::Terminal::Ansi::RESET}"
              start_col = screen_column_for_cell(geometry, start_cell)
              surface.write_abs(bounds, geometry.row, start_col, highlight)
              record_highlight_segment(tracker, geometry.row, start_col, segment_text)
            end

            def highlighted_text_segment(geometry, start_char, end_char)
              return '' if end_char <= start_char

              geometry.plain_text[start_char...end_char].to_s
            end

            def screen_column_for_cell(geometry, cell_index)
              return geometry.column_origin if cell_index <= 0
              return geometry.column_origin + geometry.visible_width if cell_index >= geometry.cells.length

              geometry.column_origin + geometry.cells[cell_index].screen_x
            end

            def char_index_for_cell(geometry, cell_index)
              cells = geometry.cells
              return 0 if cells.empty?
              return 0 if cell_index <= 0
              return geometry.plain_text.length if cell_index >= cells.length

              cells[cell_index].char_start
            end

            def cell_index_for_char(geometry, char_index, use_end_boundary: false)
              cells = geometry.cells
              return 0 if char_index.to_i <= 0
              return cells.length if cells.empty?

              match_cell_index(cells, char_index, use_end_boundary) || cells.length
            end

            def match_cell_index(cells, char_index, use_end_boundary)
              if use_end_boundary
                cells.index { |cell| cell.char_start >= char_index }
              else
                cells.index { |cell| cell.char_end > char_index }
              end
            end

            def geometry_cache_for(rendered_lines)
              cache_key = rendered_lines.object_id
              return @geometry_cache if @geometry_cache_key == cache_key && @geometry_cache

              @geometry_cache_key = cache_key
              @geometry_cache = build_geometry_cache(rendered_lines)
            end

            def build_geometry_cache(rendered_lines)
              ordered = order_geometry(geometry_entries_for(rendered_lines))
              {
                ordered: ordered,
                index_by_key: ordered.each_with_index.to_h { |geometry, index| [geometry.key, index] },
              }
            end

            def geometry_entries_for(rendered_lines)
              rendered_lines.each_with_object([]) do |(_key, info), geometries|
                geometry = info[:geometry]
                geometries << geometry if geometry
              end
            end

            def order_geometry(geometries)
              geometries.sort_by do |geometry|
                [
                  geometry.page_id || 0,
                  geometry.line_offset || 0,
                  geometry.column_id || 0,
                  geometry.row || 0,
                  geometry.column_origin || 0,
                ]
              end
            end

            def record_highlight_segment(kind, row, col, text)
              highlight_segments(kind) << { row: row, col: col, text: text }
            end

            def highlight_segments(kind)
              kind == :search_landing ? @last_search_highlight_segments : @last_selection_segments
            end

            # If selection was present on previous frame but not this one, explicitly repaint
            # the previously highlighted character cells to clear any lingering background color
            def clear_previous_selection_artifacts(surface, bounds)
              return unless @pending_clear && @last_selection_segments.any?

              clear_recorded_highlight_segments(surface, bounds, @last_selection_segments)
              @pending_clear = false
            end

            def clear_previous_search_highlight_artifacts(surface, bounds)
              return unless @pending_search_highlight_clear && @last_search_highlight_segments.any?

              clear_recorded_highlight_segments(surface, bounds, @last_search_highlight_segments)
              @pending_search_highlight_clear = false
            end

            def clear_recorded_highlight_segments(surface, bounds, segments)
              reset = Shoko::Shared::Terminal::Ansi::RESET
              segments.each do |segment|
                repaint = "#{reset}#{UI::COLOR_TEXT_PRIMARY}#{segment[:text]}#{reset}"
                surface.write_abs(bounds, segment[:row], segment[:col], repaint)
              end
              segments.clear
            end
          end
        end
      end
    end
  end
end
