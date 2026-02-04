# frozen_string_literal: true

require_relative 'base_service'

module Shoko
  module Core
    module Services
      # Domain service for layout calculations.
      class LayoutService < BaseService
        # Shared layout constants so pagination and rendering stay in sync
        SPLIT_LEFT_MARGIN = 2
        SPLIT_RIGHT_MARGIN = 2
        SPLIT_COLUMN_GAP = 4
        SPLIT_MIN_USABLE_WIDTH = 40
        MIN_COLUMN_WIDTH = 20
        CONTENT_TOP_PADDING = 2
        CONTENT_BOTTOM_PADDING = 1
        CONTENT_VERTICAL_PADDING = CONTENT_TOP_PADDING + CONTENT_BOTTOM_PADDING

        # Calculate layout metrics for given dimensions and view mode
        def calculate_metrics(width, height, view_mode)
          col_width = view_mode == :split ? split_column_width(width) : single_column_width(width)
          content_height = content_area_height(height)
          [col_width, content_height]
        end

        # Adjust height for line spacing
        def adjust_for_line_spacing(height, line_spacing)
          return 1 if height <= 0

          spacing = begin
            line_spacing&.to_sym
          rescue StandardError
            nil
          end

          return [(height + 1) / 2, 1].max if spacing == :relaxed

          multiplier = resolve_multiplier(spacing)
          adjusted = (height * multiplier).floor
          adjusted = height if multiplier >= 1.0 && adjusted < height
          [adjusted, 1].max
        end

        # Calculate center start row for content
        def calculate_center_start_row(content_height, lines_count, line_spacing)
          actual_lines = line_spacing == :relaxed ? [(lines_count * 2) - 1, 0].max : lines_count
          padding = [(content_height - actual_lines) / 2, 0].max
          [3 + padding, 3].max
        end

        # Calculate optimal column width for text content
        def calculate_optimal_column_width(available_width, _content_length)
          # Use golden ratio for optimal reading width
          optimal = (available_width * 0.618).to_i
          optimal.clamp(40, 80) # Keep within readable bounds
        end

        # Calculate padding for centered content
        def calculate_centered_padding(container_width, content_width)
          [(container_width - content_width) / 2, 0].max
        end

        def content_area_height(height)
          [height - CONTENT_VERTICAL_PADDING, 1].max
        end

        def split_column_width(width)
          usable_width = [width - SPLIT_LEFT_MARGIN - SPLIT_RIGHT_MARGIN, SPLIT_MIN_USABLE_WIDTH].max
          [(usable_width - SPLIT_COLUMN_GAP) / 2, MIN_COLUMN_WIDTH].max
        end

        def single_column_width(width)
          (width * Core::Models::ReaderSettings::SINGLE_VIEW_WIDTH_PERCENT).to_i.clamp(30, 120)
        end

        def resolve_multiplier(line_spacing)
          key = begin
            line_spacing&.to_sym
          rescue StandardError
            nil
          end
          Shoko::Core::Models::ReaderSettings::LINE_SPACING_MULTIPLIERS.fetch(key, 1.0)
        end
      end
    end
  end
end
