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
              @surface.write(@bounds, row, indent, progress_line(width, progress, filled_char, empty_char))
            end

            private

            def progress_line(width, progress, filled_char, empty_char)
              usable = [width.to_i, 14].max
              ratio = progress.to_f.clamp(0.0, 1.0)
              meter_width = [usable - 7, 8].max
              filled = (meter_width * ratio).round

              [
                "#{@tokens.divider}⟮#{@tokens.reset}",
                "#{@tokens.accent}#{filled_char * filled}#{@tokens.reset}",
                empty_segment(empty_char, meter_width, filled),
                progress_suffix(ratio),
              ].join
            end

            def empty_segment(empty_char, meter_width, filled)
              return '' unless filled < meter_width

              "#{@tokens.divider}#{empty_char * (meter_width - filled)}#{@tokens.reset}"
            end

            def progress_suffix(ratio)
              pct = (ratio * 100).round
              "#{@tokens.divider}⟯#{@tokens.reset} #{@tokens.dim}#{pct}%#{@tokens.reset}"
            end
          end
        end
      end
    end
  end
end
