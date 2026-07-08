# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module State
        # Per-frame mouse geometry for the menu: components register the
        # regions they draw (rail entries, list rows, buttons) as they render,
        # and the controller's mouse router resolves clicks and wheel turns
        # against the most recent frame. The registry also remembers the last
        # pointer position so list rows can paint a hover highlight on the
        # very frame the motion event triggers.
        #
        # Purely UI-transient state: it never touches the application store,
        # mirroring how the reader's overlay components record their own
        # click geometry at render time.
        class MenuHitRegistry
          Region = Data.define(:col, :row, :width, :height, :action) do
            def contain?(at_col, at_row)
              at_col.between?(col, col + width - 1) && at_row.between?(row, row + height - 1)
            end
          end

          def initialize
            @regions = []
            @pointer = nil
            @suspended = false
          end

          # Called once per frame by the root menu component before children render.
          def begin_frame!
            @regions = []
          end

          # Register a clickable region in terminal coordinates (1-based).
          def register(col:, row:, width:, height:, action:)
            return if @suspended || width <= 0 || height <= 0

            @regions << Region.new(col: col, row: row, width: width, height: height, action: action)
          end

          # Drops every registration made inside the block. The landing screen
          # renders a view read-only as its live preview: the view paints, but
          # its row/wheel regions must not enter the hit map — only the rail
          # stays interactive. Re-entrant so nested suspends stay balanced.
          def suspend
            previous = @suspended
            @suspended = true
            yield
          ensure
            @suspended = previous
          end

          # Resolve a click; later registrations win (they render on top).
          def hit(col, row)
            @regions.reverse_each do |region|
              return region.action if region.contain?(col, row)
            end
            nil
          end

          # Track the pointer so rows can hover-highlight while rendering.
          def pointer_moved(col, row)
            @pointer = [col, row]
          end

          attr_reader :pointer

          def hover?(col:, row:, width:, height:)
            return false unless @pointer

            at_col, at_row = @pointer
            at_col.between?(col, col + width - 1) && at_row.between?(row, row + height - 1)
          end
        end
      end
    end
  end
end
