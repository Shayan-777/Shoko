# frozen_string_literal: true

require_relative '../base_component'
require_relative '../rect'

module Shoko
  module Adapters
    module Ui
      module Components
        module Layouts
          # Horizontal layout that splits children left, center, and right.
          # Uses left/right preferred widths and assigns remaining space to center.
          class HorizontalThree < BaseComponent
            include Adapters::Ui::Constants::Ui

            def initialize(left_child, center_child, right_child)
              super(nil)
              @left_child = left_child
              @center_child = center_child
              @right_child = right_child
            end

            def do_render(surface, bounds)
              return unless @center_child

              x = bounds.x
              y = bounds.y
              w = bounds.width
              h = bounds.height

              left_width = resolve_left_width(w)
              remaining = [w - left_width, 0].max
              right_width = resolve_right_width(w, remaining)
              center_width = [w - left_width - right_width, 0].max

              if left_width.positive? && @left_child
                left_bounds = Rect.new(x: x, y: y, width: left_width, height: h)
                @left_child.render(surface, left_bounds)
              end

              if center_width.positive?
                center_bounds = Rect.new(x: x + left_width, y: y, width: center_width, height: h)
                @center_child.render(surface, center_bounds)
              end

              return unless right_width.positive? && @right_child

              right_bounds = Rect.new(x: x + left_width + center_width, y: y, width: right_width, height: h)
              @right_child.render(surface, right_bounds)
            end

            private

            def resolve_left_width(total_width)
              return 0 unless @left_child.respond_to?(:preferred_width)

              pref = @left_child.preferred_width(total_width)
              resolve_width(pref, total_width)
            end

            def resolve_right_width(total_width, remaining)
              return 0 unless @right_child.respond_to?(:preferred_width)

              pref = begin
                @right_child.preferred_width(total_width, nil, available_width: remaining)
              rescue ArgumentError
                @right_child.preferred_width(total_width)
              end
              width = resolve_width(pref, remaining)

              return 0 if width <= 0
              return 0 if remaining - width < MIN_WIDTH

              width
            end

            def resolve_width(pref, max_width)
              case pref
              when Integer
                [pref, max_width].min
              when :flexible
                max_width / 3
              when :hidden, nil
                0
              else
                0
              end
            end
          end
        end
      end
    end
  end
end
