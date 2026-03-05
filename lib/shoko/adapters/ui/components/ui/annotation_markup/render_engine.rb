# frozen_string_literal: true

require_relative 'style_support'

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          module AnnotationMarkup
            # Renders styled lines while hiding paired markup delimiters.
            class RenderEngine
              include StyleSupport

              def initialize(text:, open_at:, close_at:)
                @text = text
                @open_at = open_at
                @close_at = close_at
              end

              def render_lines(width)
                render_width = width.to_i
                return [''] if render_width <= 0

                state = initial_render_state
                clusters = AnnotationMarkup.grapheme_clusters(@text)
                index = 0
                index = process_cluster(clusters, index, render_width, state) while index < clusters.length
                finalize_lines(state)
              end

              private

              def initial_render_state
                {
                  lines: [],
                  line: +'',
                  line_width: 0,
                  needs_refresh: true,
                  active: [],
                }
              end

              def process_cluster(clusters, index, width, state)
                cluster = clusters[index]
                if escaped_prefix?(cluster, clusters, index)
                  return process_escaped_cluster(clusters, index, width, state)
                end

                cluster_idx = cluster[:index]
                return open_style(state, @open_at[cluster_idx], index) if @open_at[cluster_idx]
                return close_style(state, @close_at[cluster_idx], index) if @close_at[cluster_idx]
                return append_newline(state, index) if cluster[:text] == "\n"

                append_cluster_text(state, width, cluster[:text])
                index + 1
              end

              def escaped_prefix?(cluster, clusters, index)
                cluster[:text] == '\\' && (index + 1) < clusters.length
              end

              def process_escaped_cluster(clusters, index, width, state)
                next_cluster = clusters[index + 1]
                append_cluster_text(state, width, next_cluster[:text])
                index + 2
              end

              def open_style(state, style, index)
                state[:active] << style
                state[:needs_refresh] = true
                index + 1
              end

              def close_style(state, style, index)
                remove_style(state[:active], style)
                state[:needs_refresh] = true
                index + 1
              end

              def append_newline(state, index)
                state[:lines] << state[:line].dup
                state[:line].clear
                state[:line_width] = 0
                state[:needs_refresh] = true
                index + 1
              end

              def append_cluster_text(state, width, cluster_text)
                text = normalize_cluster(cluster_text)
                return append_tab(state, width) if text == "\t"

                append_visible_text(state, width, text)
              end

              def append_tab(state, width)
                tab_spaces(state[:line_width]).times { append_visible_text(state, width, ' ') }
              end

              def append_visible_text(state, width, text)
                cluster_width = display_width_for(text)
                return if cluster_width <= 0 || cluster_width > width

                wrap_line_if_needed(state, width, cluster_width)
                apply_refresh_if_needed(state)
                state[:line] << text
                state[:line_width] += cluster_width
              end

              def wrap_line_if_needed(state, width, cluster_width)
                return unless state[:line_width].positive? && (state[:line_width] + cluster_width > width)

                state[:lines] << state[:line].dup
                state[:line].clear
                state[:line_width] = 0
                state[:needs_refresh] = true
              end

              def apply_refresh_if_needed(state)
                return unless state[:needs_refresh]

                state[:line] << refresh_sequence(state[:active])
                state[:needs_refresh] = false
              end

              def finalize_lines(state)
                state[:lines] << state[:line].dup
                state[:lines] = [''] if state[:lines].empty?
                state[:lines]
              end
            end
          end
        end
      end
    end
  end
end
