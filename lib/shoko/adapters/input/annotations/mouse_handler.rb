# frozen_string_literal: true

module Shoko
  module Adapters::Input::Annotations
    # Handles mouse events for text selection in the reader
    class MouseHandler
      SGR_REGEX = /\e\[<(\d+);(\d+);(\d+)([Mm])/

      attr_reader :selection_start, :selection_end, :selecting

      def initialize
        reset
      end

      def mouse_sequence?(input)
        !parse_mouse_event(input).nil?
      end

      def mouse_prefix?(input)
        bytes = input.to_s.b
        return false if bytes.bytesize < 2
        return false unless bytes.getbyte(0) == 0x1B && bytes.getbyte(1) == 0x5B

        return true if bytes.bytesize == 2

        [0x3C, 0x4D].include?(bytes.getbyte(2))
      end

      # Parse ANSI mouse event
      def parse_mouse_event(input)
        return parse_sgr_mouse_event(input) if sgr_mouse_sequence?(input)
        return parse_x10_mouse_event(input) if x10_mouse_sequence?(input)

        nil
      end

      # Handle mouse event and update selection state
      def handle_event(event)
        return nil unless event

        btn = event[:button]
        rel = event[:released]
        col = event[:x]
        row = event[:y]

        if btn.zero? && !rel # Left button pressed
          start_selection(col, row)
        elsif btn == 32 && @selecting # Mouse dragged
          update_selection(col, row)
        elsif rel && @selecting # Button released
          finish_selection
        end
      end

      # Get normalized selection range
      def selection_range
        return nil unless @selection_start && @selection_end

        start_pos = @selection_start
        end_pos = @selection_end

        # Ensure start comes before end
        sy = start_pos[:y]
        ey = end_pos[:y]
        start_pos, end_pos = end_pos, start_pos if sy > ey || (sy == ey && start_pos[:x] > end_pos[:x])

        { start: start_pos, end: end_pos }
      end

      def reset
        @selecting = false
        @selection_start = nil
        @selection_end = nil
      end

      private

      def sgr_mouse_sequence?(input)
        bytes = input.to_s.b
        bytes.bytesize >= 4 && bytes.getbyte(0) == 0x1B && bytes.getbyte(1) == 0x5B && bytes.getbyte(2) == 0x3C
      end

      def x10_mouse_sequence?(input)
        bytes = input.to_s.b
        bytes.bytesize >= 6 && bytes.getbyte(0) == 0x1B && bytes.getbyte(1) == 0x5B && bytes.getbyte(2) == 0x4D
      end

      def parse_sgr_mouse_event(input)
        match = SGR_REGEX.match(input)
        return nil unless match

        {
          button: match[1].to_i,
          x: match[2].to_i - 1, # Convert to 0-based
          y: match[3].to_i - 1,
          released: match[4] == 'm',
        }
      end

      def parse_x10_mouse_event(input)
        bytes = input.to_s.b
        cb = bytes.getbyte(3) - 32
        cx = bytes.getbyte(4) - 33
        cy = bytes.getbyte(5) - 33

        return nil if cb.negative? || cx.negative? || cy.negative?

        {
          button: cb,
          x: cx,
          y: cy,
          released: (cb & 3) == 3,
        }
      end

      def start_selection(col, row)
        @selecting = true
        @selection_start = { x: col, y: row }
        @selection_end = { x: col, y: row }
        { type: :selection_start }
      end

      def update_selection(col, row)
        @selection_end = { x: col, y: row }
        { type: :selection_drag }
      end

      def finish_selection
        @selecting = false
        { type: :selection_end }
      end
    end
  end
end
