# frozen_string_literal: true

module Shoko
  module Application
    module Services
      # Calculates popup coordinates based on terminal bounds.
      class PopupPositionService
        def initialize(ui_state_reader:)
          @ui_state_reader = ui_state_reader
        end

        def calculate_popup_position(selection_end, popup_width, popup_height)
          terminal_height = @ui_state_reader.terminal_height.to_i
          terminal_width = @ui_state_reader.terminal_width.to_i
          terminal_height = 24 if terminal_height <= 0
          terminal_width = 80 if terminal_width <= 0

          end_y = selection_end[:y]
          popup_x = selection_end[:x]
          popup_y = end_y + 1

          popup_x = [terminal_width - popup_width, 1].max if popup_x + popup_width > terminal_width

          popup_y = [end_y - popup_height, 1].max if popup_y + popup_height > terminal_height

          { x: popup_x, y: popup_y }
        end
      end
    end
  end
end
