# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        # Shared geometry for the bottom-docked, left-snapped popups (the in-book
        # search results list and the dictionary definition card).
        #
        # Both panels snap to the left edge and grow upward off the status bar.
        # When the reader centers its text in a narrow column it leaves an empty
        # margin on the left; rather than overlapping the prose, the panel tucks
        # into that margin — trading the width it gives up for extra rows, so it
        # gains height instead. The overlay feeds in the content's left edge each
        # frame via #content_left_edge=; when it is absent (nothing rendered, or a
        # full-width text column) the panel falls back to its natural width.
        module BottomLeftPanel
          SIDE_GAP = 2 # breathing room kept between the panel and the reading text

          # Screen column where the reading content starts this frame (or nil).
          attr_writer :content_left_edge

          # Geometry for a left-docked, upward-growing panel of +content_count+
          # rows, reading the host's MIN_WIDTH/MAX_WIDTH/MAX_ROWS/MAX_ROWS_TALL
          # constants. Returns nil when the viewport is too small, otherwise
          # { col:, width:, bottom_row:, visible:, rule_row: }.
          def dock_layout(bounds, content_count)
            host = self.class
            return nil if bounds.width < host::MIN_WIDTH || bounds.height < 4

            width, constrained = fit_to_left_margin(bounds, host::MIN_WIDTH, host::MAX_WIDTH)
            bottom_row = bounds.height - 1 # row directly above the bar
            available = [bottom_row - 1, 1].max # keep one content row visible
            rows = row_ceiling(constrained, host::MAX_ROWS, host::MAX_ROWS_TALL)
            visible = [[content_count, rows, available].min, 1].max
            { col: 1, width: width, bottom_row: bottom_row, visible: visible, rule_row: bottom_row - visible }
          end

          # => [width, constrained?]
          #
          # +width+ is the panel width: its natural cap, shrunk to the empty left
          # margin when one is available. +constrained?+ is true when the margin
          # forced it below its natural cap (the cue to grow taller instead).
          def fit_to_left_margin(bounds, min_width, max_width)
            natural = bounds.width.clamp(min_width, max_width)
            margin = left_margin_width
            width = margin && margin >= min_width ? [natural, margin].min : natural
            [width, width < natural]
          end

          # Row ceiling for the panel: taller when width was traded away.
          def row_ceiling(constrained, base, tall)
            constrained ? tall : base
          end

          private

          # Columns free to the left of the reading content (nil when unusable).
          def left_margin_width
            left = @content_left_edge
            return nil unless left&.positive?

            left - 1 - SIDE_GAP
          end
        end
      end
    end
  end
end
