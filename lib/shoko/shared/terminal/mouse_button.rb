# frozen_string_literal: true

module Shoko
  module Shared
    module Terminal
      # Decodes the button field of an SGR mouse report.
      #
      # The encoding is a terminal protocol detail, not application policy:
      # low bits carry the button, bit 5 marks pointer motion, and bit 6 marks
      # the wheel. Input controllers and UI components both interpret the same
      # reports, and neither layer may reach into the other, so the decoding
      # lives in the shared terminal primitives beside the ANSI helpers.
      module MouseButton
        MOTION_BIT = 32
        SECONDARY = 2
        BUTTON_MASK = 0b11

        module_function

        # Primary (left) button released, without motion.
        def left_release?(event)
          button = event[:button].to_i
          event[:released] && button.nobits?(BUTTON_MASK) && button.nobits?(MOTION_BIT)
        end

        # Secondary (right) button pressed, not released, without motion.
        def right_click_press?(event)
          button = event[:button].to_i
          !event[:released] && (button & BUTTON_MASK) == SECONDARY && button.nobits?(MOTION_BIT)
        end
      end
    end
  end
end
