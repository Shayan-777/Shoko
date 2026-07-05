# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          module Landing
            # Shell geometry for the menu's master-detail layout: whether the
            # terminal is wide enough for the rail + canvas split, and how wide
            # the rail runs. The rail is sized to its content (pointer slot +
            # icon + longest label + padding) and clamped so the canvas always
            # keeps the larger share; below the wide-layout minimums the shell
            # hides the rail and views take the whole content area.
            module Layout
              Metrics = Data.define(:rail_width)

              MIN_WIDE_WIDTH = 74
              MIN_WIDE_HEIGHT = 16
              RAIL_MIN_WIDTH = 24
              RAIL_MAX_WIDTH = 32

              module_function

              def wide?(bounds)
                bounds.width >= MIN_WIDE_WIDTH && bounds.height >= MIN_WIDE_HEIGHT
              end

              def metrics(bounds, content_width:)
                Metrics.new(rail_width: rail_width(bounds, content_width))
              end

              def rail_width(bounds, content_width)
                content_width
                  .clamp(RAIL_MIN_WIDTH, RAIL_MAX_WIDTH)
                  .clamp(RAIL_MIN_WIDTH, [bounds.width / 3, RAIL_MIN_WIDTH].max)
              end
            end
          end
        end
      end
    end
  end
end
