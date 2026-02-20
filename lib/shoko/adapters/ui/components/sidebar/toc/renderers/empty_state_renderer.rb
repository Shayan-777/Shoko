# frozen_string_literal: true

module Shoko
  module Adapters::Ui::Components
    module Sidebar
      # Renders empty state message.
      class EmptyStateRenderer
        include Adapters::Ui::Constants::Ui

        MESSAGES = [
          'No chapters found',
          '',
          'Content may still be loading',
        ].freeze

        def initialize(context)
          @context = context
        end

        def render
          MESSAGES.each_with_index do |message, index|
            write_centered_message(message, index)
          end
        end

        private

        def write_centered_message(message, offset)
          x_pos = calculate_x_position(message)
          y_pos = start_y + offset
          styled_text = "#{COLOR_TEXT_DIM}#{message}#{Shoko::Shared::Terminal::Ansi::RESET}"

          @context.write(y_pos, x_pos, styled_text)
        end

        def calculate_x_position(message)
          msg_width = @context.text_metrics.visible_length(message)
          [(@context.metrics.width - msg_width) / 2, 2].max
        end

        def start_y
          ((@context.metrics.height - MESSAGES.length) / 2) + 1
        end
      end
    end
  end
end
