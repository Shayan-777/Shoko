# frozen_string_literal: true

require_relative '../../../../shared/terminal/text_metrics'
require_relative '../status_bar/palette'

module Shoko
  module Adapters
    module Ui
      module Components
        module InBookSearch
          # Lays a search result's context across the two preview rows.
          #
          # The text flows continuously — leading context, the highlighted match,
          # trailing context — and the window grows outward from the match, word by
          # word, until both rows are packed (favouring whole words). What fits is
          # then balanced across the two rows so neither is left awkwardly short:
          # short context splits evenly, long context fills the first row and spills
          # into the second. An ellipsis marks a side only when context was dropped
          # mid-sentence, so snippets that land on sentence boundaries read cleanly.
          class Snippet
            Palette = StatusBar::Palette
            ELLIPSIS = '…'
            SENTENCE_END = /[.!?]["')”’]*\z/

            def initialize(before:, match:, after:)
              @before = before.to_s
              @match = match.to_s
              @after = after.to_s
            end

            # => [[styled, visible_width], [styled, visible_width]] for both rows.
            def rows(width, background)
              @background = background
              width = [width.to_i, 1].max
              tokens, match_index = tokenize
              return [empty_row, empty_row] if tokens.empty?

              lo, hi = grow_window(tokens, match_index, width)
              first, second = balance(window(tokens, lo, hi), width)
              [render(first), render(second)]
            end

            private

            def tokenize
              before = words(@before)
              after = words(@after)
              match = @match.empty? ? [] : [token(@match, :match)]
              [before + match + after, @match.empty? ? 0 : before.length]
            end

            def words(text)
              text.split(/\s+/).reject(&:empty?).map { |word| token(word, :text) }
            end

            # Expand outward from the match (after first, then before) while the
            # window still fits within two rows.
            def grow_window(tokens, match_index, width)
              widths = tokens.map { |t| visible_length(t[:text]) }
              lo = hi = match_index.clamp(0, tokens.length - 1)
              loop do
                grew = false
                if hi + 1 < tokens.length && fits_two?(widths[lo..(hi + 1)], width)
                  hi += 1
                  grew = true
                end
                if lo.positive? && fits_two?(widths[(lo - 1)..hi], width)
                  lo -= 1
                  grew = true
                end
                break unless grew
              end
              [lo, hi]
            end

            def fits_two?(widths, width)
              line_count(widths, width) <= 2
            end

            def line_count(widths, width)
              lines = 1
              col = 0
              widths.each do |w|
                need = col.zero? ? w : w + 1
                if col + need <= width
                  col += need
                else
                  lines += 1
                  col = w
                end
              end
              lines
            end

            # Add the ellipsis markers for any context dropped mid-sentence.
            def window(tokens, low, high)
              slice = tokens[low..high]
              slice = [ellipsis] + slice if low.positive? && !sentence_end?(tokens[low - 1][:text])
              slice += [ellipsis] if high < tokens.length - 1 && !sentence_end?(tokens[high][:text])
              slice
            end

            # Split tokens across two rows: evenly when short (≤ one row), otherwise
            # fill the first row and spill the rest into the second. Both rows pack
            # at word boundaries and never exceed +width+ (any overflow is dropped
            # cleanly rather than clipped mid-word).
            def balance(tokens, width)
              total = tokens.sum { |t| visible_length(t[:text]) } + [tokens.length - 1, 0].max
              target = total <= width ? (total / 2.0).ceil : width

              _, split = take_row(tokens, 0, width, target)
              split = 1 if split.zero? && tokens.any? # force-place an over-long first word
              second, = take_row(tokens, split, width, width)
              [tokens.first(split), second]
            end

            # Greedily pack tokens from +start+ into one row up to +target+ columns
            # (never beyond +width+), breaking only at word boundaries.
            # => [row_tokens, next_index].
            def take_row(tokens, start, width, target)
              row = []
              col = 0
              index = start
              while index < tokens.length
                step = visible_length(tokens[index][:text])
                step += 1 unless col.zero?
                break if col + step > width

                row << tokens[index]
                col += step
                index += 1
                break if col >= target
              end
              [row, index]
            end

            def render(tokens)
              return empty_row if tokens.empty?

              styled = +''
              vis = 0
              tokens.each_with_index do |t, i|
                if i.positive?
                  styled << span(' ', Palette::LIST_TEXT_FG)
                  vis += 1
                end
                styled << span(t[:text], style_for(t[:kind]))
                vis += visible_length(t[:text])
              end
              [styled, vis]
            end

            def token(text, kind)
              { text: text, kind: kind }
            end

            def ellipsis
              token(ELLIPSIS, :dim)
            end

            def empty_row
              ['', 0]
            end

            def sentence_end?(word)
              word.match?(SENTENCE_END)
            end

            def style_for(kind)
              case kind
              when :match then "#{Palette::BOLD}#{Palette::LIST_MATCH_FG}"
              when :dim then Palette::LIST_DIM_FG
              else Palette::LIST_TEXT_FG
              end
            end

            def span(text, foreground)
              "#{Palette::RESET}#{@background}#{foreground}#{text}"
            end

            def visible_length(text)
              Shoko::Shared::Terminal::TextMetrics.visible_length(text.to_s)
            end
          end
        end
      end
    end
  end
end
