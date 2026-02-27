# frozen_string_literal: true

require_relative '../../../../shared/terminal/text_metrics'
require_relative 'theme_tokens'

module Shoko
  module Adapters
    module Ui
      module Components
        module MenuDesign
          # Shared horizontal progress bar rendering for menu workflows.
          class ProgressRenderer
            def initialize(surface, bounds, tokens: ThemeTokens.new)
              @surface = surface
              @bounds = bounds
              @tokens = tokens
            end

            def render(row:, indent:, width:, progress:, filled_char: '━', empty_char: '─')
              usable = [width.to_i, 14].max
              ratio = progress.to_f.clamp(0.0, 1.0)
              pct = (ratio * 100).round
              meter_w = [usable - 7, 8].max
              filled = (meter_w * ratio).round
              line = "#{@tokens.divider}⟮#{@tokens.reset}"
              line += "#{@tokens.accent}#{filled_char * filled}#{@tokens.reset}"
              line += "#{@tokens.divider}#{empty_char * (meter_w - filled)}#{@tokens.reset}" if filled < meter_w
              line += "#{@tokens.divider}⟯#{@tokens.reset} #{@tokens.dim}#{pct}%#{@tokens.reset}"
              @surface.write(@bounds, row, indent, line)
            end
          end
        end
      end
    end
  end
end
