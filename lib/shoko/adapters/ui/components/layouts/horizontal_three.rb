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

            Segment = Data.define(:child, :x, :y, :width, :height)

            def initialize(left_child, center_child, right_child)
              super(nil)
              @left_child = left_child
              @center_child = center_child
              @right_child = right_child
            end

            def do_render(surface, bounds)
              return unless @center_child

              left_width, center_width, right_width = resolved_widths(bounds.width)
              render_segment(surface, segment(@left_child, bounds, bounds.x, left_width))
              render_segment(surface, segment(@center_child, bounds, bounds.x + left_width, center_width))
              render_segment(surface, segment(@right_child, bounds, bounds.x + left_width + center_width, right_width))
            end

            private

            def resolved_widths(total_width)
              left_width = resolve_left_width(total_width)
              remaining = [total_width - left_width, 0].max
              right_width = resolve_right_width(total_width, remaining)
              center_width = [total_width - left_width - right_width, 0].max
              [left_width, center_width, right_width]
            end

            def segment(child, bounds, x_pos, width)
              Segment.new(child: child, x: x_pos, y: bounds.y, width: width, height: bounds.height)
            end

            def render_segment(surface, segment)
              return unless segment.child && segment.width.positive?

              child_bounds = Rect.new(x: segment.x, y: segment.y, width: segment.width, height: segment.height)
              segment.child.render(surface, child_bounds)
            end

            def resolve_left_width(total_width)
              return 0 unless @left_child

              pref = @left_child.preferred_width(total_width)
              resolve_width(pref, total_width)
            end

            def resolve_right_width(total_width, remaining)
              return 0 unless @right_child

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
