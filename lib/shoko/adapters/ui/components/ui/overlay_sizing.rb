# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          # Calculates overlay dimensions based on viewport bounds.
          class OverlaySizing
            def initialize(width_ratio:, width_padding:, min_width:, height_ratio:, height_padding:, min_height:)
              @width_ratio = width_ratio
              @width_padding = width_padding
              @min_width = min_width
              @height_ratio = height_ratio
              @height_padding = height_padding
              @min_height = min_height
            end

            def width_for(total_width)
              clamp_dimension(total_width, ratio: @width_ratio, padding: @width_padding, min: @min_width)
            end

            def height_for(total_height)
              clamp_dimension(total_height, ratio: @height_ratio, padding: @height_padding, min: @min_height)
            end

            private

            def clamp_dimension(total, ratio:, padding:, min:)
              base = [(total * ratio).floor, total - padding].min
              upper = total - padding
              lower = [min, upper].min
              base.clamp(lower, upper)
            end
          end
        end
      end
    end
  end
end
