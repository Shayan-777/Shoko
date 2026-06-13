# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        # Shared mouse hit-testing for the bottom-docked bar overlays (in-book
        # search, TOC, notes, dictionary, translator). Each overlay records its
        # clickable list geometry for the current frame as it renders; the
        # mouse router then asks #hit_test what a click landed on.
        #
        # A list face records the real row geometry so a click resolves to the
        # item index under the cursor. A non-list face (a text card or an
        # editor) records only its top rule with `count: 0`, so clicks on the
        # panel are inert while a click above it still reads as a dismiss.
        module OverlayMouseTarget
          # @param rule_row [Integer] 1-based row of the panel's top hairline
          # @param col [Integer] 1-based left column of the panel
          # @param width [Integer] panel width in columns
          # @param visible [Integer] number of item slots currently shown
          # @param rows_per [Integer] rendered rows per item (1, or 3 for blocks)
          # @param scroll [Integer] index of the first visible item
          # @param count [Integer] total selectable items (0 for a non-list face)
          def record_overlay_geometry(rule_row:, col:, width:, visible:, rows_per:, scroll:, count:)
            @overlay_hit = {
              rule_row: rule_row.to_i, col: col.to_i, width: width.to_i,
              visible: [visible.to_i, 0].max, rows_per: [rows_per.to_i, 1].max,
              scroll: scroll.to_i, count: [count.to_i, 0].max
            }
          end

          def clear_overlay_geometry
            @overlay_hit = nil
          end

          # Resolve a 1-based terminal click against this frame's geometry.
          #
          # @return [Integer] the clicked item index (activate it)
          # @return [:inside] on the panel but not on an item (no-op)
          # @return [:outside] above the panel — a dismiss gesture
          def hit_test(column, row)
            geo = @overlay_hit
            return :inside unless geo
            return :outside if row.to_i < geo[:rule_row]
            return :inside unless clickable_item_area?(geo, column.to_i, row.to_i)

            slot = (row.to_i - (geo[:rule_row] + 1)) / geo[:rows_per]
            return :inside if slot >= geo[:visible]

            index = geo[:scroll] + slot
            index < geo[:count] ? index : :inside
          end

          private

          # True when (column, row) is inside the panel's selectable item region
          # (below the rule, within its columns, on a list face that has items).
          def clickable_item_area?(geo, column, row)
            return false if geo[:count].zero?
            return false if row < geo[:rule_row] + 1
            return false if column < geo[:col] || column > geo[:col] + geo[:width] - 1

            true
          end
        end
      end
    end
  end
end
