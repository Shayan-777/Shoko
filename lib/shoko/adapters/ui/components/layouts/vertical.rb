# frozen_string_literal: true

require_relative '../base_component'
require_relative '../rect'

module Shoko
  module Adapters
    module Ui
      module Components
        module Layouts
          # Simple vertical layout that stacks children top-to-bottom
          # Respects preferred heights; assigns remaining space to first flexible child
          class Vertical < BaseComponent
            AllocationState = Data.define(:heights, :fill_children)

            def initialize(children)
              super(nil)
              @children = children
            end

            def do_render(surface, bounds)
              return if @children.nil? || @children.empty?

              # Calculate heights using new contract
              heights = calculate_child_heights(bounds.height)

              # Render children
              cursor_y = bounds.y
              @children.each_with_index do |child, i|
                height = heights[i] || 0
                next if height <= 0

                child_bounds = Rect.new(x: bounds.x, y: cursor_y, width: bounds.width, height: height)
                child.render(surface, child_bounds)
                cursor_y += height
              end
            end

            private

            def calculate_child_heights(total_height)
              heights = Array.new(@children.length, 0)
              remaining, fill_children = allocate_fixed_heights(heights, total_height)
              distribute_fill_heights(heights, fill_children, remaining)
              heights
            end

            def allocate_fixed_heights(heights, total_height)
              remaining = total_height
              state = AllocationState.new(heights: heights, fill_children: [])

              @children.each_with_index do |child, index|
                pref = child ? child.preferred_height(total_height) : :flexible
                remaining = assign_child_height(state, index, pref, remaining)
              end

              [remaining, state.fill_children]
            end

            def assign_child_height(state, index, pref, remaining)
              case pref
              when Integer
                height = [pref, remaining].min
                state.heights[index] = height
                remaining - height
              when :fill
                state.fill_children << index
                remaining
              else
                state.heights[index] = 0
                remaining
              end
            end

            def distribute_fill_heights(heights, fill_children, remaining)
              return if fill_children.empty?

              target_height = remaining.positive? ? (remaining / fill_children.size) : 0
              fill_children.each { |index| heights[index] = target_height }
            end
          end
        end
      end
    end
  end
end
