# frozen_string_literal: true

require_relative '../../../core/ports/layout_metrics'
require_relative '../../../core/services/layout_service'

module Shoko
  module Adapters::Runtime::SessionState
    # Application adapter implementing the LayoutMetrics port.
    # Reads layout constants from LayoutService, providing a clean
    # interface for adapters to access layout configuration.
    class LayoutMetricsAdapter
      include Core::Ports::LayoutMetrics

      # Left margin for split view mode.
      #
      # @return [Integer] Margin in characters
      def split_left_margin
        Core::Services::LayoutService::SPLIT_LEFT_MARGIN
      end

      # Right margin for split view mode.
      #
      # @return [Integer] Margin in characters
      def split_right_margin
        Core::Services::LayoutService::SPLIT_RIGHT_MARGIN
      end

      # Gap between columns in split view mode.
      #
      # @return [Integer] Gap in characters
      def split_column_gap
        Core::Services::LayoutService::SPLIT_COLUMN_GAP
      end

      # Minimum usable width for split view.
      #
      # @return [Integer] Width in characters
      def split_min_usable_width
        Core::Services::LayoutService::SPLIT_MIN_USABLE_WIDTH
      end

      # Minimum column width for content.
      #
      # @return [Integer] Width in characters
      def min_column_width
        Core::Services::LayoutService::MIN_COLUMN_WIDTH
      end

      # Top padding for content area.
      #
      # @return [Integer] Padding in lines
      def content_top_padding
        Core::Services::LayoutService::CONTENT_TOP_PADDING
      end

      # Bottom padding for content area.
      #
      # @return [Integer] Padding in lines
      def content_bottom_padding
        Core::Services::LayoutService::CONTENT_BOTTOM_PADDING
      end
    end
  end
end
