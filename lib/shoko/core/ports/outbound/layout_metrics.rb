# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Port interface for accessing layout metric values.
        # Encapsulates layout constants behind a clean interface,
        # allowing adapters to access layout configuration without
        # directly coupling to core service implementation details.
        #
        # @example Implementing this port
        #   class LayoutMetricsAdapter
        #     include Shoko::Core::Ports::Outbound::LayoutMetrics
        #
        #     def split_left_margin
        #       2
        #     end
        #   end
        module LayoutMetrics
          # Left margin for split view mode.
          #
          # @return [Integer] Margin in characters
          def split_left_margin
            raise NotImplementedError, "#{self.class} must implement #split_left_margin"
          end

          # Right margin for split view mode.
          #
          # @return [Integer] Margin in characters
          def split_right_margin
            raise NotImplementedError, "#{self.class} must implement #split_right_margin"
          end

          # Gap between columns in split view mode.
          #
          # @return [Integer] Gap in characters
          def split_column_gap
            raise NotImplementedError, "#{self.class} must implement #split_column_gap"
          end

          # Minimum usable width for split view.
          #
          # @return [Integer] Width in characters
          def split_min_usable_width
            raise NotImplementedError, "#{self.class} must implement #split_min_usable_width"
          end

          # Minimum column width for content.
          #
          # @return [Integer] Width in characters
          def min_column_width
            raise NotImplementedError, "#{self.class} must implement #min_column_width"
          end

          # Top padding for content area.
          #
          # @return [Integer] Padding in lines
          def content_top_padding
            raise NotImplementedError, "#{self.class} must implement #content_top_padding"
          end

          # Bottom padding for content area.
          #
          # @return [Integer] Padding in lines
          def content_bottom_padding
            raise NotImplementedError, "#{self.class} must implement #content_bottom_padding"
          end

          # Total vertical padding (top + bottom).
          #
          # @return [Integer] Total padding in lines
          def content_vertical_padding
            content_top_padding + content_bottom_padding
          end
        end
      end
    end
  end
end
