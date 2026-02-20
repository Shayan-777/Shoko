# frozen_string_literal: true

module Shoko
  module Adapters::Ui::Components
    Rect = Struct.new(:x, :y, :width, :height, keyword_init: true) do
      def bottom
        y + height - 1
      end

      def right
        x + width - 1
      end
    end
  end
end
