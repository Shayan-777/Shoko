# frozen_string_literal: true

require_relative '../../../../shared/terminal/text_metrics'
require_relative 'theme_tokens'

module Shoko
  module Adapters
    module Ui
      module Components
        module MenuDesign
          # Consistent search field rendering for menu list screens.
          class SearchFieldRenderer
            def initialize(surface, bounds, tokens: ThemeTokens.new)
              @surface = surface
              @bounds = bounds
              @tokens = tokens
            end

            def render(label:, query:, cursor:, row:, indent:, width:, active:)
              label_text = label.to_s.upcase
              @surface.write(@bounds, row, indent, "#{@tokens.dim}#{label_text}#{@tokens.reset}")

              usable = [width.to_i, 10].max
              inner = [usable - 4, 1].max
              text = query.to_s.dup
              c = cursor.to_i.clamp(0, text.length)
              text.insert(c, @tokens.cursor_glyph)
              clipped = Shoko::Shared::Terminal::TextMetrics.truncate_to(text, inner)
              body = Shoko::Shared::Terminal::TextMetrics.pad_right(clipped, inner)

              border_color = active ? @tokens.accent : @tokens.divider
              text_color = active ? @tokens.primary : @tokens.dim
              line = "#{border_color}[#{@tokens.reset} #{text_color}#{body}#{@tokens.reset} #{border_color}]#{@tokens.reset}"
              @surface.write(@bounds, row + 1, indent, line)
            end
          end
        end
      end
    end
  end
end
