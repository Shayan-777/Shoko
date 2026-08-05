# frozen_string_literal: true

require 'shoko/core/models/block_type'
require 'shoko/adapters/support/content_block_codec'
require 'shoko/shared/terminal/ansi'
require 'shoko/shared/terminal/text_metrics'
require_relative '../status_bar/palette'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Lays an article's content blocks out as styled reading lines.
          #
          # The reading pane is segment-based (`[[text, style], …]` per row), so
          # structure survives all the way to the terminal: headings stand out,
          # list items keep their markers and hanging indent, quotes get a
          # gutter, code keeps its spacing, and inline emphasis is real bold /
          # italic rather than lost.
          #
          # Wrapping is display-width aware and style-preserving — a run that
          # spans a line break keeps its emphasis on both rows — and CJK or
          # emoji text is measured in cells, not characters.
          class RssArticleLayout
            Palette = StatusBar::Palette
            Ansi = Shoko::Shared::Terminal::Ansi
            TextMetrics = Shoko::Shared::Terminal::TextMetrics
            BlockType = Shoko::Core::Models::BlockType

            QUOTE_GUTTER = '│ '
            CODE_INDENT = '  '
            LIST_INDENT = '  '
            RULE_CHAR = '─'
            RULE_WIDTH_RATIO = 3
            BULLET = '•'
            MIN_WIDTH = 8
            # h1/h2 are article-level headings and take the brighter tone.
            TOP_HEADING_LEVEL = 2

            # Mutable accumulator for one wrap pass: the rows built so far, the
            # cells used on the current row, and the room each row has.
            WrapState = Struct.new(:rows, :used, :room)

            # One laid-out row of the article.
            #
            # +segments+ is what the renderer writes. The rest is what makes the
            # row interactive: +text+ is the row's selectable prose (without the
            # gutter, marker, or indent that precede it), +column+ is how far in
            # that prose starts, and +index+ is its offset in the article's
            # selectable stream — so a screen position maps to a character in
            # the article and back.
            # +prefix+ is the decoration drawn before the prose (a quote
            # gutter, a list marker, code indent); +content+ is the prose
            # itself. They are kept apart so a highlight can be applied to the
            # words without ever painting the decoration.
            ReadingLine = Data.define(:prefix, :content, :text, :column, :index) do
              def initialize(prefix: [], content: [], text: '', column: 0, index: 0)
                super
              end

              def segments = prefix + content

              def selectable? = !text.empty?

              def end_index = index + text.length
            end

            # Types whose consecutive blocks form one visual unit: a list is not
            # double-spaced between its items, and a code listing is not
            # double-spaced between its lines. Everything else gets a blank line.
            TIGHT_TYPES = %i[list_item code].freeze

            def initialize(width:)
              @width = [width.to_i, MIN_WIDTH].max
            end

            # @param blocks [Array<ContentBlock>, Array<Hash>] parsed or stored
            # @return [Array<ReadingLine>]
            def call(blocks)
              self.class.index_rows(rows(blocks))
            end

            # The article's rows before they are numbered, so a caller that
            # prepends its own rows (a title, a byline) can number the whole
            # reading surface in one pass and keep the stream contiguous.
            #
            # @return [Array<Hash>] :segments, :text, :column
            def rows(blocks)
              built = []
              previous = nil

              Shoko::Adapters::Support::ContentBlockCodec.load(blocks).each do |block|
                type = BlockType.canonical(block.type)
                built << blank_row if blank_line_before?(previous, type)
                built.concat(block_lines(block))
                previous = type
              end
              built
            end

            # A blank spacer row: drawn as nothing, selectable as nothing.
            def blank_row = { prefix: [], content: [], text: '', column: 0 }

            # Numbers rows into one selectable stream. Rows are joined by a
            # newline, so a selection spanning rows reads as separate lines.
            def self.index_rows(rows)
              cursor = 0
              rows.map do |row|
                line = ReadingLine.new(
                  prefix: row[:prefix] || [], content: row[:content] || [],
                  text: row[:text].to_s, column: row[:column].to_i, index: cursor
                )
                cursor += line.text.length + 1
                line
              end
            end

            private

            def blank_line_before?(previous, type)
              return false if previous.nil?

              !(TIGHT_TYPES.include?(type) && previous == type)
            end

            def block_lines(block)
              case BlockType.canonical(block.type)
              when :heading then heading_lines(block)
              when :quote then quote_lines(block)
              when :code then code_lines(block)
              when :list_item then list_item_lines(block)
              when :caption then styled_lines(block, Palette::LANDING_DIM_FG)
              when :rule then [rule_line]
              else styled_lines(block, Palette::LANDING_TEXT_FG)
              end
            end

            # ----- block shapes -----

            def heading_lines(block)
              tone = block.heading_level.to_i <= TOP_HEADING_LEVEL ? Palette::LANDING_TITLE_FG : Palette::LANDING_TEXT_FG
              wrap(block.segments, @width).map do |row|
                styled = row.map { |text, styles| [text, style_colour(styles.merge(bold: true), tone)] }
                row_for(content: styled)
              end
            end

            def quote_lines(block)
              gutter = [QUOTE_GUTTER, Palette::LANDING_DIM_FG]
              wrap(block.segments, @width - display_width(QUOTE_GUTTER)).map do |row|
                row_for(prefix: [gutter], content: toned(row, Palette::LANDING_DIM_FG))
              end
            end

            # Code keeps its own spacing, so it is indented and clipped rather
            # than re-wrapped — rewrapping code changes what it means.
            def code_lines(block)
              room = [@width - display_width(CODE_INDENT), 1].max
              content = [[TextMetrics.truncate_to(block.text, room), Palette::DICT_TRANS_FG]]
              [row_for(prefix: [[CODE_INDENT, nil]], content: content)]
            end

            # The marker sits on the first row and later rows align under the
            # text, so a wrapped item reads as one item.
            def list_item_lines(block)
              indent = LIST_INDENT * [block.level - 1, 0].max
              marker = "#{block.metadata[:marker] || BULLET} "
              room = [@width - display_width(indent) - display_width(marker), 1].max

              wrap(block.segments, room).each_with_index.map do |row, index|
                row_for(prefix: [[indent, nil], list_prefix(marker, index)],
                        content: toned(row, Palette::LANDING_TEXT_FG))
              end
            end

            # Assembles a row from the decoration that precedes the prose and
            # the prose itself, recording where the prose starts so a click can
            # be resolved to a character rather than to a bullet or a gutter.
            def row_for(content:, prefix: [])
              {
                prefix: prefix,
                content: content,
                text: content.map(&:first).join,
                column: prefix.sum { |text, _style| display_width(text) },
              }
            end

            def list_prefix(marker, index)
              return [marker, Palette::LIST_POINTER_FG] if index.zero?

              [' ' * display_width(marker), nil]
            end

            def toned(row, tone)
              row.map { |text, styles| [text, style_colour(styles, tone)] }
            end

            def styled_lines(block, tone)
              wrap(block.segments, @width).map { |row| row_for(content: toned(row, tone)) }
            end

            # Decoration, not prose: drawn, never selected.
            def rule_line
              { prefix: [[RULE_CHAR * [@width / RULE_WIDTH_RATIO, 1].max, Palette::LANDING_FAINT_FG]],
                content: [], text: '', column: 0 }
            end

            # ----- inline styles -----

            # Emphasis is composed onto the block's own tone, so a bold run in a
            # quote stays quote-coloured. Links take the accent colour so they
            # are visible as links without an escape-sequence hyperlink.
            def style_colour(styles, tone)
              base = styles[:link] ? Palette::LIST_POINTER_FG : tone
              base = Palette::DICT_TRANS_FG if styles[:code]
              attributes = +''
              attributes << Ansi::BOLD if styles[:bold]
              attributes << Ansi::ITALIC if styles[:italic]
              attributes << Ansi::DIM if styles[:dim]
              "#{attributes}#{base}"
            end

            # ----- wrapping -----

            # Greedy word wrap over styled runs. Words carry their own styles so
            # a break inside an emphasised run keeps the emphasis on both rows;
            # a word longer than the line is cell-split rather than overflowing.
            def wrap(segments, width)
              state = WrapState.new([[]], 0, [width.to_i, 1].max)
              tokens(segments).each { |text, styles| place(state, text, styles) }
              state.rows.reject(&:empty?).map { |row| merge_runs(row) }
            end

            def place(state, text, styles)
              # Leading spaces on a row, and the space a break replaces, are
              # both consumed by the break rather than drawn.
              return if text == ' ' && (state.rows.last.empty? || overflows?(state, text))

              open_next_row(state) if overflows?(state, text) && !state.rows.last.empty?
              return split_long_word(state, text, styles) if display_width(text) > state.room

              state.rows.last << [text, styles]
              state.used += display_width(text)
            end

            def overflows?(state, text)
              state.used + display_width(text) > state.room
            end

            def open_next_row(state)
              state.rows << []
              state.used = 0
            end

            # A single word wider than the line is broken on cell boundaries so
            # it can never overflow the panel.
            def split_long_word(state, text, styles)
              TextMetrics.wrap_cells(text, state.room).each_with_index do |chunk, index|
                state.rows << [] if index.positive?
                state.rows.last << [chunk, styles]
                state.used = display_width(chunk)
              end
            end

            # Split into words while keeping each word's styles, so wrapping can
            # break between words without losing emphasis.
            def tokens(segments)
              Array(segments).flat_map do |segment|
                segment.text.split(/(\s+)/).filter_map do |part|
                  next if part.empty?

                  [part.match?(/\A\s+\z/) ? ' ' : part, segment.styles]
                end
              end
            end

            # Adjacent runs sharing a style become one segment, so a line costs
            # as few terminal writes as it needs.
            def merge_runs(row)
              row.each_with_object([]) do |(text, styles), acc|
                if acc.last && acc.last[1] == styles
                  acc.last[0] += text
                else
                  acc << [text.dup, styles]
                end
              end
            end

            def display_width(text) = TextMetrics.visible_length(text.to_s)
          end
        end
      end
    end
  end
end
