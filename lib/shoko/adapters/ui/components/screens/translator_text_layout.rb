# frozen_string_literal: true

require 'shoko/shared/terminal/text_metrics'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Builds and caches grapheme-aware wrapped layouts for translator panes.
          class TranslatorTextLayout
            Cluster = Data.define(:text, :start_index, :end_index, :column_start, :column_end)
            Line = Data.define(:text, :start_index, :end_index, :clusters)

            def initialize
              @cache_key = nil
              @cache_value = nil
            end

            def build(text, width)
              key = [text.to_s, [width.to_i, 1].max]
              return @cache_value if @cache_key == key

              @cache_key = key.freeze
              @cache_value = build_uncached(key[0], key[1]).freeze
            end

            def empty_line(index = 0)
              line('', index, index, [])
            end

            def visual_cursor(layouts, cursor)
              layouts.each_with_index do |entry, index|
                cluster = cursor_cluster(entry, cursor)
                return [index, cluster.column_start] if cluster
                return [index, line_end_column(entry)] if cursor_at_visual_line_end?(layouts, index, cursor)
              end
              [[layouts.length - 1, 0].max, 0]
            end

            def index_for_column(line_layout, column)
              line_layout.clusters.each do |cluster|
                return [cluster.start_index, nil] if column < cluster.column_start
                next unless column < cluster.column_end

                midpoint = cluster.column_start + ((cluster.column_end - cluster.column_start) / 2.0)
                index = column < midpoint ? cluster.start_index : cluster.end_index
                return [index, cluster]
              end
              [line_layout.end_index, nil]
            end

            private

            def cursor_cluster(entry, cursor)
              entry.clusters.find { |cluster| cursor >= cluster.start_index && cursor < cluster.end_index }
            end

            def cursor_at_visual_line_end?(layouts, index, cursor)
              entry = layouts[index]
              return false unless cursor == entry.end_index

              following = layouts[index + 1]
              !following || following.start_index != cursor
            end

            def line_end_column(entry)
              entry.clusters.last&.column_end || 0
            end

            def build_uncached(text, width)
              state = initial_state(width)
              text.each_grapheme_cluster { |cluster| process_cluster(state, cluster) }
              push_line(state)
              state[:lines]
            end

            def initial_state(width)
              {
                width: width,
                index: 0,
                line_start: 0,
                line_width: 0,
                text: +'',
                clusters: [],
                lines: [],
              }
            end

            def process_cluster(state, cluster)
              if cluster == "\n"
                push_line(state)
                state[:index] += cluster.length
                reset_line(state)
                return
              end

              cluster_width = [Shoko::Shared::Terminal::TextMetrics.display_width_for(cluster), 1].max
              if state[:clusters].any? && state[:line_width] + cluster_width > state[:width]
                push_line(state)
                reset_line(state)
              end
              append_cluster(state, cluster, cluster_width)
            end

            def append_cluster(state, cluster, width)
              start_index = state[:index]
              state[:index] += cluster.length
              state[:clusters] << Cluster.new(
                text: cluster,
                start_index: start_index,
                end_index: state[:index],
                column_start: state[:line_width],
                column_end: state[:line_width] + width
              )
              state[:line_width] += width
              state[:text] << cluster
            end

            def push_line(state)
              state[:lines] << line(state[:text], state[:line_start], state[:index], state[:clusters])
            end

            def reset_line(state)
              state[:line_start] = state[:index]
              state[:line_width] = 0
              state[:text] = +''
              state[:clusters] = []
            end

            def line(text, start_index, end_index, clusters)
              Line.new(
                text: text.dup.freeze,
                start_index: start_index,
                end_index: end_index,
                clusters: clusters.dup.freeze
              )
            end
          end
        end
      end
    end
  end
end
