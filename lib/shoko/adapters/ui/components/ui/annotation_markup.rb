# frozen_string_literal: true

require 'shoko/shared/terminal/text_metrics'
require_relative 'annotation_markup/cursor_map_builder'
require_relative 'annotation_markup/cursor_position_engine'
require_relative 'annotation_markup/pair_finder'
require_relative 'annotation_markup/render_engine'

module Shoko
  module Adapters
    module Ui
      module Components
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
                render_engine.render_lines(width)
              end

              def cursor_position(cursor, width)
                cursor_position_engine.cursor_position(cursor, width)
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
                cursor_map_builder.build(width)
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

              def render_engine
                @render_engine ||= RenderEngine.new(text: @text, open_at: @open_at, close_at: @close_at)
              end

              def cursor_position_engine
                @cursor_position_engine ||= CursorPositionEngine.new(
                  text: @text,
                  open_at: @open_at,
                  close_at: @close_at
                )
              end

              def cursor_map_builder
                @cursor_map_builder ||= CursorMapBuilder.new(text: @text, open_at: @open_at, close_at: @close_at)
              end
            end

            def self.find_pairs(text)
              PairFinder.new(text, markers: MARKERS, literal_styles: LITERAL_STYLES).find_pairs
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
          end
        end
      end
    end
  end
end
