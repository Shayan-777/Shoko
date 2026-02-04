# frozen_string_literal: true

module Shoko
  module Adapters::Output::Ui::Components
    module UI
      # Shared cursor blinking behavior for text editors.
      module CursorBlink
        BLINK_IDLE_AFTER = 0.7
        BLINK_PERIOD = 1.0
        CURSOR_GLYPH = '|'

        def initialize_cursor_blink
          @cursor_last_input_at = monotonic_time
        end

        def record_cursor_activity
          @cursor_last_input_at = monotonic_time
        end

        def cursor_visible?
          cursor_state.first
        end

        def cursor_glyph
          cursor_state.last
        end

        def cursor_state(now = monotonic_time)
          last = @cursor_last_input_at || now
          elapsed = now - last
          return [true, CURSOR_GLYPH] if elapsed < BLINK_IDLE_AFTER

          phase = (elapsed - BLINK_IDLE_AFTER) % BLINK_PERIOD
          visible = phase < (BLINK_PERIOD / 2.0)
          [visible, visible ? CURSOR_GLYPH : ' ']
        end

        private

        def monotonic_time
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
