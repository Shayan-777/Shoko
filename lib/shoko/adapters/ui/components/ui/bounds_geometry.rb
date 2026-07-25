# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          # Translates 1-based component-local coordinates into absolute
          # terminal cells within a component's bounds.
          #
          # The surface and the line drawer both map local positions onto the
          # same grid; an off-by-one that lived in only one of them would
          # misplace exactly the content the other drew.
          module BoundsGeometry
            module_function

            # @return [Array(Integer, Integer)] absolute [row, col]
            def absolute_position(bounds, row, col)
              [bounds.y + row - 1, bounds.x + col - 1]
            end
          end
        end
      end
    end
  end
end
