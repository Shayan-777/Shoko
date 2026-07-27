# frozen_string_literal: true

module Shoko
  module Shared
    module Terminal
      # The one coordinate-system boundary for terminal mouse input.
      module Coordinates
        module_function

        def mouse_to_terminal(mouse_x, mouse_y)
          { x: mouse_x.to_i + 1, y: mouse_y.to_i + 1 }
        end

        def terminal_to_mouse(terminal_x, terminal_y)
          { x: [terminal_x.to_i - 1, 0].max, y: [terminal_y.to_i - 1, 0].max }
        end
      end
    end
  end
end
