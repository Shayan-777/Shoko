# frozen_string_literal: true

require_relative '../../../../shared/terminal/text_metrics'
require_relative 'theme_tokens'

module Shoko
  module Adapters
    module Ui
      module Components
        module MenuDesign
          # Unified status and empty-state rendering for menu screens.
          class StatusRenderer
            def initialize(surface, bounds, tokens: ThemeTokens.new)
              @surface = surface
              @bounds = bounds
              @tokens = tokens
            end

            def render_status(row:, indent:, left:, right: nil, width: nil, left_color: nil, right_color: nil)
              colors = { left: left_color || @tokens.dim, right: right_color || @tokens.dim }
              @surface.write(@bounds, row, indent, "#{colors[:left]}#{left}#{@tokens.reset}")

              right_layout = right_text_layout(left, right, indent, width)
              return unless right_layout

              @surface.write(@bounds,
                             row,
                             right_layout[:col],
                             "#{colors[:right]}#{right_layout[:text]}#{@tokens.reset}")
            end

            def render_empty(row:, indent:, message:, color: nil)
              color ||= @tokens.dim
              @surface.write(@bounds, row, indent, "#{color}#{message}#{@tokens.reset}")
            end

            private

            def right_text_layout(left, right, indent, width)
              return nil if right.to_s.empty?

              left_width = Shoko::Shared::Terminal::TextMetrics.visible_length(left.to_s)
              area_right = area_right_boundary(indent, width)
              min_col = indent + left_width + 2
              clipped_right = clipped_right_text(right, area_right, min_col)
              right_width = Shoko::Shared::Terminal::TextMetrics.visible_length(clipped_right)

              {
                col: [area_right - right_width + 1, min_col].max,
                text: clipped_right,
              }
            end

            def area_right_boundary(indent, width)
              width.to_i.positive? ? [indent + width.to_i - 1, @bounds.width].min : @bounds.width
            end

            def clipped_right_text(right, area_right, min_col)
              max_right_width = [area_right - min_col + 1, 1].max
              Shoko::Shared::Terminal::TextMetrics.truncate_to(right.to_s, max_right_width)
            end
          end
        end
      end
    end
  end
end
