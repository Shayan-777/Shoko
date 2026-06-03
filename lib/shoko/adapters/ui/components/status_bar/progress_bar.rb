# frozen_string_literal: true

require_relative 'palette'

module Shoko
  module Adapters
    module Ui
      module Components
        module StatusBar
          # Renders a smooth, sub-character progress bar.
          #
          # Each cell carries eight horizontal steps (▏▎▍▌▋▊▉█), so the fill moves
          # in 1/8th-cell increments rather than jumping a whole column at a time —
          # the detail that makes the bar feel smooth as the reader turns pages.
          module ProgressBar
            # Eighth-width left-aligned blocks, index 0 (empty) .. 8 (full).
            EIGHTHS = [' ', '▏', '▎', '▍', '▌', '▋', '▊', '▉', '█'].freeze
            FULL = '█'
            GROOVE = '─'

            module_function

            # Returns a styled bar of exactly +cells+ visible columns.
            #
            # fraction: 0.0..1.0 progress.
            # fill_rgb:  [r, g, b] color for the filled portion (e.g. the format color);
            #            falls back to the brand accent when nil.
            def render(fraction:, cells:, fill_rgb: nil)
              count = cells.to_i
              return '' if count <= 0

              filled = clamp_fraction(fraction) * count
              full_cells = [filled.floor, count].min
              partial_index = full_cells < count ? ((filled - full_cells) * 8).round : 0

              "#{Palette::RESET}#{compose(count, full_cells, partial_index, fill_rgb)}"
            end

            # Builds exactly +count+ cells: full blocks, one optional partial block,
            # then a groove for the remainder — never over- or under-running the width.
            def compose(count, full_cells, partial_index, fill_rgb)
              fill = FULL * full_cells
              used = full_cells

              if partial_index.positive? && used < count
                fill += EIGHTHS[partial_index]
                used += 1
              end

              groove = GROOVE * [count - used, 0].max
              "#{fill_style(fill_rgb)}#{fill}#{groove_style}#{groove}"
            end

            def fill_style(fill_rgb)
              Palette::TRACK_BG + Palette.fg(fill_rgb || Palette::BRAND_RGB)
            end

            def groove_style
              Palette::TRACK_BG + Palette::FAINT_FG
            end

            def clamp_fraction(value)
              f = value.to_f
              return 0.0 if f.negative?
              return 1.0 if f > 1.0

              f
            end
          end
        end
      end
    end
  end
end
