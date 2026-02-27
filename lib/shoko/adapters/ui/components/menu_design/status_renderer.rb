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

            def render_status(row:, indent:, left:, right: nil, left_color: nil, right_color: nil)
              left_color ||= @tokens.dim
              right_color ||= @tokens.dim
              @surface.write(@bounds, row, indent, "#{left_color}#{left}#{@tokens.reset}")
              return if right.to_s.empty?

              left_width = Shoko::Shared::Terminal::TextMetrics.visible_length(left.to_s)
              right_width = Shoko::Shared::Terminal::TextMetrics.visible_length(right.to_s)
              min_col = indent + left_width + 2
              max_col = @bounds.width - right_width - 1
              col = [max_col, min_col].max
              @surface.write(@bounds, row, col, "#{right_color}#{right}#{@tokens.reset}")
            end

            def render_empty(row:, indent:, message:, color: nil)
              color ||= @tokens.dim
              @surface.write(@bounds, row, indent, "#{color}#{message}#{@tokens.reset}")
            end
          end
        end
      end
    end
  end
end
