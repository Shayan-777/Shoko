# frozen_string_literal: true

require_relative '../../../../shared/terminal/ansi'

module Shoko
  module Adapters::Ui::Components
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

      # Provides centered overlay placement and frame geometry helpers.
      class OverlayLayout
        attr_reader :origin_x, :origin_y, :width, :height

        def initialize(origin_x:, origin_y:, width:, height:)
          @origin_x = origin_x
          @origin_y = origin_y
          @width = width
          @height = height
        end

        def self.centered(bounds, width:, height:)
          origin_x = [(bounds.width - width) / 2, 1].max + 1
          origin_y = [(bounds.height - height) / 2, 1].max + 1
          new(origin_x: origin_x, origin_y: origin_y, width: width, height: height)
        end

        # Backward-compatible accessors used by some overlays.
        def start_col
          origin_x
        end

        def start_row
          origin_y
        end

        def inner_x
          origin_x + 1
        end

        def inner_y
          origin_y + 1
        end

        def inner_width
          width - 2
        end

        def inner_height
          height - 2
        end

        def fill_background(surface, bounds, background:)
          reset = Shoko::Shared::Terminal::Ansi::RESET
          height.times do |offset|
            surface.write(bounds, origin_y + offset, origin_x, "#{background}#{' ' * width}#{reset}")
          end
        end
      end
    end
  end
end
