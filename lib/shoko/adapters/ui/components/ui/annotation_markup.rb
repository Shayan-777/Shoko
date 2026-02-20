# frozen_string_literal: true

require_relative '../../../../shared/terminal/text_metrics'

module Shoko
  module Adapters::Ui::Components
    module Ui
      # Inline markup styling for annotation notes.
      #
      # Supported markers (org/markdown-inspired):
      # - *bold*
      # - /italic/
      # - _underline_
      # - -strike- or +strike+
      # - =code= or `code`
      # - ~verbatim~
      #
      # Markers disappear once closed; styles apply only after the closing marker.
      module AnnotationMarkup
        MARKERS = {
          '*' => :bold,
          '/' => :italic,
          '_' => :underline,
          '-' => :strike,
          '+' => :strike,
          '=' => :code,
          '`' => :code,
          '~' => :verbatim,
        }.freeze

        STYLE_ON = {
          bold: "\e[1m",
          italic: "\e[3m",
          underline: "\e[4m",
          strike: "\e[9m",
          code: "\e[7m",
          verbatim: "\e[2m",
        }.freeze

        STYLE_RESET = "\e[22;23;24;29;27m"
        STYLE_ORDER = %i[bold italic underline strike code verbatim].freeze
        LITERAL_STYLES = %i[code verbatim].freeze

        # Stateful renderer that hides matched markers and applies styles.
        class Styler
          def initialize(text)
            @text = text.to_s
            @open_at, @close_at = AnnotationMarkup.find_pairs(@text)
          end

          def render_lines(width)
            w = width.to_i
            return [''] if w <= 0

            lines = []
            line = +''
            line_width = 0
            needs_refresh = true
            active = []

            clusters = AnnotationMarkup.grapheme_clusters(@text)
            i = 0
            while i < clusters.length
              cluster = clusters[i]
              idx = cluster[:index]

              if cluster[:text] == '\\' && (i + 1) < clusters.length
                i += 1
                next_cluster = clusters[i]
                line, line_width, needs_refresh = append_cluster_result(lines, line, w, next_cluster[:text],
                                                                        active, needs_refresh, line_width)
                i += 1
                next
              end

              if @open_at[idx]
                active << @open_at[idx]
                needs_refresh = true
                i += 1
                next
              end

              if @close_at[idx]
                remove_style(active, @close_at[idx])
                needs_refresh = true
                i += 1
                next
              end

              if cluster[:text] == "\n"
                lines << line.dup
                line.clear
                line_width = 0
                needs_refresh = true
                i += 1
                next
              end

              line, line_width, needs_refresh = append_cluster_result(lines, line, w, cluster[:text],
                                                                      active, needs_refresh, line_width)
              i += 1
            end

            lines << line.dup
            lines = [''] if lines.empty?
            lines
          end

          def cursor_position(cursor, width)
            w = width.to_i
            return [0, 0] if w <= 0

            cursor_index = cursor.to_i
            line = 0
            col = 0
            active = []

            clusters = AnnotationMarkup.grapheme_clusters(@text)
            i = 0
            while i < clusters.length
              cluster = clusters[i]
              idx = cluster[:index]
              return [line, col] if idx >= cursor_index

              if cluster[:text] == '\\' && (i + 1) < clusters.length
                i += 1
                next_cluster = clusters[i]
                idx = next_cluster[:index]
                return [line, col] if idx >= cursor_index

                line, col = advance_cursor(line, col, w, next_cluster[:text])
                i += 1
                next
              end

              if @open_at[idx]
                active << @open_at[idx]
                i += 1
                next
              end

              if @close_at[idx]
                remove_style(active, @close_at[idx])
                i += 1
                next
              end

              if cluster[:text] == "\n"
                line += 1
                col = 0
                i += 1
                next
              end

              line, col = advance_cursor(line, col, w, cluster[:text])
              i += 1
            end

            [line, col]
          end

          def move_left(cursor, width)
            map = cursor_map(width)
            idx = map_index_for_cursor(cursor, width, map)
            return cursor if idx.nil? || idx <= 0

            map[idx - 1][:index]
          end

          def move_right(cursor, width)
            map = cursor_map(width)
            idx = map_index_for_cursor(cursor, width, map)
            return cursor if idx.nil?

            next_pos = map[idx + 1]
            next_pos ? next_pos[:index] : cursor
          end

          def move_up(cursor, width)
            map = cursor_map(width)
            line, col = cursor_position(cursor, width)
            target_line = [line - 1, 0].max
            cursor_index_for(target_line, col, map)
          end

          def move_down(cursor, width)
            map = cursor_map(width)
            line, col = cursor_position(cursor, width)
            max_line = map.last ? map.last[:line] : 0
            target_line = [line + 1, max_line].min
            cursor_index_for(target_line, col, map)
          end

          def style_line(line)
            self.class.new(line).render_lines(10_000).first.to_s
          end

          private

          def cursor_map(width)
            w = width.to_i
            return [{ index: 0, line: 0, col: 0 }] if w <= 0

            positions = []
            line = 0
            col = 0
            positions << { index: 0, line: line, col: col }

            clusters = AnnotationMarkup.grapheme_clusters(@text)
            i = 0
            while i < clusters.length
              cluster = clusters[i]
              idx = cluster[:index]
              text = cluster[:text]
              escaped = false

              if text == '\\' && (i + 1) < clusters.length
                i += 1
                cluster = clusters[i]
                idx = cluster[:index]
                text = cluster[:text]
                escaped = true
              end

              if !escaped && (@open_at[idx] || @close_at[idx])
                i += 1
                next
              end

              if text == "\n"
                line += 1
                col = 0
                positions << { index: idx + text.length, line: line, col: col }
                i += 1
                next
              end

              visible = normalize_cluster(text)
              cw = if visible == "\t"
                     tab_spaces(col)
                   else
                     display_width_for(visible)
                   end

              if cw <= 0 || cw > w
                i += 1
                next
              end

              if col.positive? && (col + cw > w)
                line += 1
                col = 0
              end

              last = positions.last
              if !last || last[:index] != idx || last[:line] != line || last[:col] != col
                positions << { index: idx, line: line, col: col }
              end
              col += cw
              positions << { index: idx + text.length, line: line, col: col }
              i += 1
            end

            if positions.last && positions.last[:index] != @text.length
              positions << { index: @text.length, line: line, col: col }
            end

            positions
          end

          def map_index_for_cursor(cursor, width, map)
            cursor_idx = cursor.to_i.clamp(0, @text.length)
            line, col = cursor_position(cursor_idx, width)

            map.rindex { |pos| pos[:index] <= cursor_idx && pos[:line] == line && pos[:col] == col } ||
              map.index { |pos| pos[:line] == line && pos[:col] == col }
          end

          def cursor_index_for(line, col, map)
            line_positions = map.select { |pos| pos[:line] == line }
            return map.last[:index] if line_positions.empty?

            candidate = line_positions.select { |pos| pos[:col] <= col }.max_by { |pos| pos[:col] }
            candidate ||= line_positions.min_by { |pos| pos[:col] }
            candidate[:index]
          end

          def append_cluster_result(lines, line, width, cluster_text, active, needs_refresh, line_width)
            text = normalize_cluster(cluster_text)
            if text == "\t"
              spaces = tab_spaces(line_width)
              spaces.times do
                line, line_width, needs_refresh = append_cluster_result(lines, line, width, ' ',
                                                                        active, needs_refresh, line_width)
              end
              return [line, line_width, needs_refresh]
            end

            cw = display_width_for(text)
            return [line, line_width, needs_refresh] if cw <= 0
            return [line, line_width, needs_refresh] if cw > width

            if line_width.positive? && (line_width + cw > width)
              lines << line.dup
              line.clear
              line_width = 0
              needs_refresh = true
            end

            if needs_refresh
              line << refresh_sequence(active)
              needs_refresh = false
            end

            line << text
            line_width += cw
            [line, line_width, needs_refresh]
          end

          def advance_cursor(line, col, width, cluster_text)
            text = normalize_cluster(cluster_text)
            if text == "\t"
              spaces = tab_spaces(col)
              return advance_cursor(line, col, width, ' ' * spaces)
            end

            cw = display_width_for(text)
            return [line, col] if cw <= 0
            return [line, col] if cw > width

            if col.positive? && (col + cw > width)
              line += 1
              col = 0
            end
            [line, col + cw]
          end

          def normalize_cluster(cluster)
            return ' ' if cluster == "\r"

            cluster
          end

          def refresh_sequence(active)
            seq = STYLE_RESET.dup
            active_styles(active).each { |style| seq << STYLE_ON.fetch(style) }
            seq
          end

          def active_styles(active)
            STYLE_ORDER.select { |style| active.include?(style) }
          end

          def remove_style(active, style)
            idx = active.rindex(style)
            active.delete_at(idx) if idx
          end

          def display_width_for(cluster)
            Shoko::Shared::Terminal::TextMetrics.display_width_for(cluster)
          end

          def tab_spaces(col)
            size = Shoko::Shared::Terminal::TextMetrics::TAB_SIZE
            size - (col % size)
          end
        end

        def self.find_pairs(text)
          open_at = {}
          close_at = {}
          stack = []

          i = 0
          while i < text.length
            ch = text[i]
            if ch == '\\' && (i + 1) < text.length
              i += 2
              next
            end

            style = MARKERS[ch]
            if style
              can_open, can_close = delimiter_flags(text, i)

              if literal_mode?(stack)
                if stack.last && stack.last[:marker] == ch && can_close
                  open = stack.pop
                  open_at[open[:index]] = open[:style]
                  close_at[i] = open[:style]
                end
              elsif stack.last && stack.last[:marker] == ch && can_close
                open = stack.pop
                open_at[open[:index]] = open[:style]
                close_at[i] = open[:style]
              elsif can_open
                stack << { marker: ch, style: style, index: i }
              end
            end

            i += 1
          end

          [open_at, close_at]
        end

        def self.grapheme_clusters(text)
          clusters = []
          index = 0
          text.to_s.each_grapheme_cluster do |cluster|
            clusters << { text: cluster, index: index }
            index += cluster.length
          end
          clusters
        end

        def self.literal_mode?(stack)
          stack.any? { |entry| LITERAL_STYLES.include?(entry[:style]) }
        end

        def self.delimiter_flags(text, idx)
          prev = idx.positive? ? text[idx - 1] : nil
          nxt = (idx + 1) < text.length ? text[idx + 1] : nil

          prev_ws = whitespace?(prev)
          next_ws = whitespace?(nxt)
          prev_word = word_char?(prev)
          next_word = word_char?(nxt)
          prev_punct = prev && !prev_ws && !prev_word
          next_punct = nxt && !next_ws && !next_word

          can_open = !next_ws && (prev_ws || prev_punct || prev.nil?)
          can_close = !prev_ws && (next_ws || next_punct || nxt.nil?)

          [can_open, can_close]
        end

        def self.whitespace?(char)
          char.nil? || char.match?(/\s/)
        end

        def self.word_char?(char)
          return false if char.nil?

          char.match?(/\p{Alnum}/)
        rescue StandardError
          char.match?(/[A-Za-z0-9]/)
        end
      end
    end
  end
end
