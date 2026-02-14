# frozen_string_literal: true

require_relative 'base_service'
require_relative '../models/selection_anchor'
require_relative '../ports/rendered_content_reader'

module Shoko
  module Core
    module Services
      # Service to normalize selection ranges and extract text from rendered_lines
      # Centralizes logic used by UIController and MouseableReader
      #
      # This service follows hexagonal architecture principles:
      # - Rendered content reading goes through RenderedContentReader port
      class SelectionService < BaseService
        def initialize(coordinate_service:, logger: nil)
          super(logger: logger)
          @coordinate_service = coordinate_service
        end

        # Extract selected text from selection_range using rendered_lines in state
        # @param selection_range [Hash] {:start=>{x:,y:}, :end=>{x:,y:}}
        # @param rendered_lines [Hash<Integer, Hash>] mapping of line_id => {row:, col:, col_end:, width:, text:}
        # @return [String]
        def extract_text(selection_range, rendered_lines)
          return '' unless selection_range && rendered_lines && !rendered_lines.empty?

          anchors = resolve_anchors(selection_range, rendered_lines)
          return '' unless anchors

          extract_text_between_anchors(anchors[:start], anchors[:end], rendered_lines)
        end

        # Normalize a selection range using the coordinate service and rendered_lines
        #
        # @param rendered_content_reader [Core::Ports::RenderedContentReader] Port for reading rendered content
        # @param selection_range [Hash]
        # @return [Hash, nil] normalized range or nil when normalization fails
        def normalize_range(rendered_content_reader:, selection_range:)
          return nil unless selection_range
          return selection_range if anchor_range?(selection_range)

          rendered = rendered_content_reader.rendered_lines
          @coordinate_service.normalize_selection_range(selection_range, rendered)
        rescue StandardError => e
          logger.debug('selection.normalize_range failed', error: e.message)
          nil
        end

        private

        def anchor_range?(range)
          return false unless range.is_a?(Hash)

          start_anchor = range[:start] || range['start']
          start_anchor.is_a?(Hash) && (start_anchor.key?(:geometry_key) || start_anchor.key?('geometry_key'))
        end

        def resolve_anchors(selection_range, rendered_lines)
          normalized = @coordinate_service.normalize_selection_range(selection_range, rendered_lines)
          return nil unless normalized

          start_anchor = Shoko::Core::Models::SelectionAnchor.from(normalized[:start])
          end_anchor = Shoko::Core::Models::SelectionAnchor.from(normalized[:end])
          return nil unless start_anchor && end_anchor

          { start: start_anchor, end: end_anchor }
        end

        def extract_text_between_anchors(start_anchor, end_anchor, rendered_lines)
          geometry_index = build_geometry_index(rendered_lines)
          return '' if geometry_index.empty?

          ordered = order_geometry(geometry_index.values)
          range = geometry_range(ordered, start_anchor, end_anchor)
          return '' unless range

          collect_text_segments(ordered[range], start_anchor, end_anchor).join("\n")
        end

        def geometry_range(ordered, start_anchor, end_anchor)
          start_idx = ordered.find_index { |geo| geo.key == start_anchor.geometry_key }
          end_idx = ordered.find_index { |geo| geo.key == end_anchor.geometry_key }
          return nil unless start_idx && end_idx

          start_idx..end_idx
        end

        def collect_text_segments(geometries, start_anchor, end_anchor)
          geometries.filter_map do |geometry|
            extract_segment(geometry, start_anchor, end_anchor)
          end
        end

        def extract_segment(geometry, start_anchor, end_anchor)
          start_cell = geometry.key == start_anchor.geometry_key ? start_anchor.cell_index : 0
          end_cell = geometry.key == end_anchor.geometry_key ? end_anchor.cell_index : geometry.cells.length
          return nil if end_cell < start_cell

          start_char = char_index_for_cell(geometry, start_cell)
          end_char = char_index_for_cell(geometry, end_cell)
          geometry.plain_text[start_char...end_char]
        end

        def build_geometry_index(rendered_lines)
          rendered_lines.each_with_object({}) do |(_key, info), acc|
            geometry = info[:geometry]
            next unless geometry

            acc[geometry.key] = geometry
          end
        end

        def order_geometry(geometries)
          geometries.sort_by do |geo|
            [geo.page_id || 0, geo.line_offset || 0, geo.column_id || 0, geo.row || 0, geo.column_origin || 0]
          end
        end

        def char_index_for_cell(geometry, cell_index)
          cells = geometry.cells
          return 0 if cells.empty?

          if cell_index <= 0
            0
          elsif cell_index >= cells.length
            geometry.plain_text.length
          else
            cells[cell_index].char_start
          end
        end
      end
    end
  end
end
