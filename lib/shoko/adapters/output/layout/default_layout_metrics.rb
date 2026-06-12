# frozen_string_literal: true

require 'shoko/application/ports/outbound/layout_metrics'

module Shoko
  module Adapters
    module Output
      module Layout
        # Default implementation of LayoutMetrics port.
        # Provides standard layout values without depending on adapters.
        # Useful for testing and as a fallback when no adapter is available.
        class DefaultLayoutMetrics
          include Shoko::Application::Ports::Outbound::LayoutMetrics

          # Left margin for split view mode.
          #
          # @return [Integer] Margin in characters
          def split_left_margin
            2
          end

          # Right margin for split view mode.
          #
          # @return [Integer] Margin in characters
          def split_right_margin
            2
          end

          # Gap between columns in split view mode.
          #
          # @return [Integer] Gap in characters
          def split_column_gap
            4
          end

          # Minimum usable width for split view.
          #
          # @return [Integer] Width in characters
          def split_min_usable_width
            40
          end

          # Minimum column width for content.
          #
          # @return [Integer] Width in characters
          def min_column_width
            20
          end

          # Top padding for content area.
          #
          # @return [Integer] Padding in lines
          def content_top_padding
            2
          end

          # Bottom padding for content area.
          #
          # @return [Integer] Padding in lines
          def content_bottom_padding
            1
          end
        end
      end
    end
  end
end
