# frozen_string_literal: true

module Shoko
  module Application
    module Services
      # Calculates popup coordinates based on terminal bounds.
      class PopupPositionService
        def initialize(terminal_service:)
          @terminal_service = terminal_service
        end

        def calculate_popup_position(selection_end, popup_width, popup_height)
          terminal_height, terminal_width = @terminal_service.size

          end_y = selection_end[:y]
          popup_x = selection_end[:x]
          popup_y = end_y + 1

          if popup_x + popup_width > terminal_width
            popup_x = [terminal_width - popup_width, 1].max
          end

          if popup_y + popup_height > terminal_height
            popup_y = [end_y - popup_height, 1].max
          end

          { x: popup_x, y: popup_y }
        end
      end
    end
  end
end
