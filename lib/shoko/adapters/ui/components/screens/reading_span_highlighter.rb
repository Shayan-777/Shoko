# frozen_string_literal: true

require 'shoko/shared/terminal/ansi'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Paints character ranges of a laid-out reading row.
          #
          # The row's prose is already split into styled runs; a span cuts
          # across them wherever it happens to start and end, so the runs are
          # re-cut at the span boundaries and the covered part takes an extra
          # attribute on top of whatever colour it already had. Emphasis, links
          # and quote tones therefore survive being highlighted.
          #
          # Two features drive this: the live text selection and in-article
          # find. Both mark ranges of the same character stream, so they share
          # one implementation and compose — a find match inside the selection
          # shows both attributes.
          module ReadingSpanHighlighter
            Ansi = Shoko::Shared::Terminal::Ansi

            # A saved note is a lasting mark on the text, so it reads as a
            # highlight rather than as the transient reverse a selection uses.
            ANNOTATION = "#{Ansi::BOLD}#{Ansi::UNDERLINE}".freeze
            SELECTION = Ansi::REVERSE
            MATCH = Ansi::UNDERLINE
            CURRENT_MATCH = "#{Ansi::REVERSE}#{Ansi::UNDERLINE}".freeze

            module_function

            # @param line [RssArticleLayout::ReadingLine]
            # @param spans [Array<Hash>] :range (in stream coordinates), :style
            # @return [Array<Array(String, String)>] segments ready to draw
            def call(line, spans)
              applicable = spans_for(line, spans)
              return line.segments if applicable.empty?

              line.prefix + paint(line, applicable)
            end

            # Spans that actually touch this row, converted to row-local
            # character offsets.
            def spans_for(line, spans)
              Array(spans).filter_map do |span|
                range = span[:range]
                next unless range

                from = [range.first - line.index, 0].max
                to = [range.last - line.index, line.text.length].min
                next if to <= from

                { from: from, to: to, style: span[:style] }
              end
            end

            def paint(line, spans)
              cursor = 0
              line.content.flat_map do |text, colour|
                pieces = cut(text, cursor, spans, colour)
                cursor += text.length
                pieces
              end
            end

            # Re-cuts one run at every span boundary that falls inside it.
            def cut(text, offset, spans, colour)
              boundaries = cut_points(text, offset, spans)
              boundaries.each_cons(2).filter_map do |from, to|
                next if to <= from

                piece = text[from...to]
                next if piece.nil? || piece.empty?

                [piece, "#{attributes_at(offset + from, spans)}#{colour}"]
              end
            end

            def cut_points(text, offset, spans)
              points = [0, text.length]
              spans.each do |span|
                points << (span[:from] - offset)
                points << (span[:to] - offset)
              end
              points.map { |point| point.clamp(0, text.length) }.uniq.sort
            end

            # A character inside several spans takes all their attributes.
            def attributes_at(index, spans)
              spans.select { |span| index >= span[:from] && index < span[:to] }
                   .map { |span| span[:style] }.uniq.join
            end
          end
        end
      end
    end
  end
end
