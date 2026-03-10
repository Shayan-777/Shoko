# frozen_string_literal: true

require_relative '../../../core/ports/outbound/layout_metrics'
require_relative '../../../core/services/default_layout_metrics'

module Shoko
  module Adapters
    module Output
      module Layout
        # Application adapter implementing the LayoutMetrics port.
        # Exposes layout metrics to adapters without direct application-layer references.
        class LayoutMetricsAdapter
          include Core::Ports::Outbound::LayoutMetrics

          def initialize(layout_service: nil, fallback_metrics: nil)
            @layout_service = layout_service
            @fallback_metrics = fallback_metrics || Shoko::Core::Services::DefaultLayoutMetrics.new
          end

          # Left margin for split view mode.
          #
          # @return [Integer] Margin in characters
          def split_left_margin
            @layout_service&.split_left_margin || @fallback_metrics.split_left_margin
          end

          # Right margin for split view mode.
          #
          # @return [Integer] Margin in characters
          def split_right_margin
            @layout_service&.split_right_margin || @fallback_metrics.split_right_margin
          end

          # Gap between columns in split view mode.
          #
          # @return [Integer] Gap in characters
          def split_column_gap
            @layout_service&.split_column_gap || @fallback_metrics.split_column_gap
          end

          # Minimum usable width for split view.
          #
          # @return [Integer] Width in characters
          def split_min_usable_width
            @layout_service&.split_min_usable_width || @fallback_metrics.split_min_usable_width
          end

          # Minimum column width for content.
          #
          # @return [Integer] Width in characters
          def min_column_width
            @layout_service&.min_column_width || @fallback_metrics.min_column_width
          end

          # Top padding for content area.
          #
          # @return [Integer] Padding in lines
          def content_top_padding
            @layout_service&.content_top_padding || @fallback_metrics.content_top_padding
          end

          # Bottom padding for content area.
          #
          # @return [Integer] Padding in lines
          def content_bottom_padding
            @layout_service&.content_bottom_padding || @fallback_metrics.content_bottom_padding
          end
        end
      end
    end
  end
end
