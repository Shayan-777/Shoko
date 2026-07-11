# frozen_string_literal: true

require_relative 'style_primitives'

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          module AnnotationMarkup
            # Computes visible cursor location within styled annotation text.
            class CursorPositionEngine
              include StylePrimitives

              def initialize(text:, open_at:, close_at:)
                @text = text
                @open_at = open_at
                @close_at = close_at
              end

              def cursor_position(cursor, width)
                cursor_width = width.to_i
                return [0, 0] if cursor_width <= 0

                state = { line: 0, col: 0, width: cursor_width, cursor_index: cursor.to_i }
                clusters = AnnotationMarkup.grapheme_clusters(@text)
                index = 0
                while index < clusters.length
                  cluster = clusters[index]
                  return [state[:line], state[:col]] if cluster[:index] >= state[:cursor_index]

                  index = process_cluster(clusters, index, state)
                end
                [state[:line], state[:col]]
              end

              private

              def process_cluster(clusters, index, state)
                cluster = clusters[index]
                return process_escaped_cluster(clusters, index, state) if escaped_prefix?(cluster, clusters, index)

                return index + 1 if marker_cluster?(cluster[:index])
                return process_newline(index, state) if cluster[:text] == "\n"

                advance_cursor(state, state[:width], cluster[:text])
                index + 1
              end

              def escaped_prefix?(cluster, clusters, index)
                cluster[:text] == '\\' && (index + 1) < clusters.length
              end

              def process_escaped_cluster(clusters, index, state)
                next_cluster = clusters[index + 1]
                return index + 1 if next_cluster[:index] >= state[:cursor_index]

                advance_cursor(state, state[:width], next_cluster[:text])
                index + 2
              end

              def marker_cluster?(cluster_index)
                @open_at[cluster_index] || @close_at[cluster_index]
              end

              def process_newline(index, state)
                state[:line] += 1
                state[:col] = 0
                index + 1
              end

              def advance_cursor(state, width, cluster_text)
                text = normalize_cluster(cluster_text)
                return advance_cursor(state, width, ' ' * tab_spaces(state[:col])) if text == "\t"

                cluster_width = display_width_for(text)
                return if cluster_width <= 0 || cluster_width > width

                if state[:col].positive? && (state[:col] + cluster_width > width)
                  state[:line] += 1
                  state[:col] = 0
                end
                state[:col] += cluster_width
              end
            end
          end
        end
      end
    end
  end
end
