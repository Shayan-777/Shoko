# frozen_string_literal: true

require 'shoko/shared/terminal/ansi'

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          # Provides centered overlay placement and frame geometry helpers.
          class OverlayLayout
            attr_reader :origin_x, :origin_y, :width, :height

            def initialize(origin_x:, origin_y:, width:, height:)
              @origin_x = origin_x
              @origin_y = origin_y
              @width = width
              @height = height
            end

            def self.centered(bounds, width:, height:)
              origin_x = [(bounds.width - width) / 2, 1].max + 1
              origin_y = [(bounds.height - height) / 2, 1].max + 1
              new(origin_x: origin_x, origin_y: origin_y, width: width, height: height)
            end

            def inner_x
              origin_x + 1
            end

            def inner_y
              origin_y + 1
            end

            def inner_width
              width - 2
            end

            def inner_height
              height - 2
            end

            def fill_background(surface, bounds, background:)
              reset = Shoko::Shared::Terminal::Ansi::RESET
              height.times do |offset|
                surface.write(bounds, origin_y + offset, origin_x, "#{background}#{' ' * width}#{reset}")
              end
            end
          end
        end
      end
    end
  end
end
