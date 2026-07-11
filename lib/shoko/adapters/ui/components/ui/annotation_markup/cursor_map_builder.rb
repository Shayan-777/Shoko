# frozen_string_literal: true

require_relative 'style_primitives'

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          module AnnotationMarkup
            # Builds cursor-index to visible-position mapping for navigation.
            class CursorMapBuilder
              include StylePrimitives

              def initialize(text:, open_at:, close_at:)
                @text = text
                @open_at = open_at
                @close_at = close_at
              end

              def build(width)
                map_width = width.to_i
                return [{ index: 0, line: 0, col: 0 }] if map_width <= 0

                state = initial_state
                clusters = AnnotationMarkup.grapheme_clusters(@text)
                index = 0
                index = process_cluster(clusters, index, map_width, state) while index < clusters.length
                append_terminal_position(state)
                state[:positions]
              end

              private

              def initial_state
                {
                  line: 0,
                  col: 0,
                  positions: [{ index: 0, line: 0, col: 0 }],
                }
              end

              def process_cluster(clusters, index, width, state)
                cluster = clusters[index]
                if escaped_prefix?(cluster, clusters, index)
                  return process_escaped_cluster(clusters, index, width, state)
                end

                return index + 1 if marker_cluster?(cluster[:index])
                return process_newline(index, cluster, state) if cluster[:text] == "\n"

                append_visible_position(cluster[:text], cluster[:index], width, state)
                index + 1
              end

              def escaped_prefix?(cluster, clusters, index)
                cluster[:text] == '\\' && (index + 1) < clusters.length
              end

              def process_escaped_cluster(clusters, index, width, state)
                next_cluster = clusters[index + 1]
                append_visible_position(next_cluster[:text], next_cluster[:index], width, state)
                index + 2
              end

              def marker_cluster?(cluster_index)
                @open_at[cluster_index] || @close_at[cluster_index]
              end

              def process_newline(index, cluster, state)
                state[:line] += 1
                state[:col] = 0
                append_position(state, cluster[:index] + cluster[:text].length)
                index + 1
              end

              def append_visible_position(cluster_text, cluster_index, width, state)
                text = normalize_cluster(cluster_text)
                cluster_width = text == "\t" ? tab_spaces(state[:col]) : display_width_for(text)
                return if cluster_width <= 0 || cluster_width > width

                wrap_if_needed(cluster_width, width, state)
                append_index_if_needed(state, cluster_index)
                state[:col] += cluster_width
                append_position(state, cluster_index + cluster_text.length)
              end

              def wrap_if_needed(cluster_width, width, state)
                return unless state[:col].positive? && (state[:col] + cluster_width > width)

                state[:line] += 1
                state[:col] = 0
              end

              def append_index_if_needed(state, index)
                last = state[:positions].last
                return if last && last[:index] == index && last[:line] == state[:line] && last[:col] == state[:col]

                append_position(state, index)
              end

              def append_position(state, index)
                state[:positions] << { index: index, line: state[:line], col: state[:col] }
              end

              def append_terminal_position(state)
                return if state[:positions].last && state[:positions].last[:index] == @text.length

                append_position(state, @text.length)
              end
            end
          end
        end
      end
    end
  end
end
