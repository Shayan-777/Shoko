# frozen_string_literal: true

require_relative 'palette'
require_relative '../../../../shared/terminal/text_metrics'

module Shoko
  module Adapters
    module Ui
      module Components
        module StatusBar
          # Places a left cluster and a right cluster onto a single full-width
          # slate row: left flush-left, right flush-right, bar background filling
          # the gap between them.
          #
          # When the two clusters can't both fit, the right cluster (page/progress —
          # short and important) is preserved and the left cluster (title/chapter)
          # is truncated with an ellipsis. The returned line always paints every
          # column with the bar background so the strip reads as one solid surface.
          module BarComposer
            ELLIPSIS = '…'

            module_function

            # left/right: { text: styled_string, width: visible_columns }.
            def compose(width:, left:, right:)
              total = width.to_i
              return '' if total <= 0

              right_text, right_width = clamp(right, total)
              left_text, left_width = fit_left(left, total - right_width - 1)

              gap = [total - left_width - right_width, 0].max
              filler = Palette.span(' ' * gap, Palette::TEXT_FG)

              "#{left_text}#{filler}#{right_text}#{Palette::RESET}"
            end

            # Truncate the left cluster to the available width, appending an ellipsis
            # when something was dropped. Never returns a negative budget.
            def fit_left(left, budget)
              text = left[:text].to_s
              width = left[:width].to_i
              avail = [budget, 0].max
              return [text, width] if width <= avail
              return ['', 0] if avail <= 1

              truncated = Shoko::Shared::Terminal::TextMetrics.truncate_to(text, avail - 1)
              ["#{truncated}#{Palette.span(ELLIPSIS, Palette::DIM_FG)}", avail]
            end

            # Guard against a right cluster that alone exceeds the bar width.
            def clamp(right, total)
              text = right[:text].to_s
              width = right[:width].to_i
              return [text, width] if width <= total

              [Shoko::Shared::Terminal::TextMetrics.truncate_to(text, total), total]
            end
          end
        end
      end
    end
  end
end
