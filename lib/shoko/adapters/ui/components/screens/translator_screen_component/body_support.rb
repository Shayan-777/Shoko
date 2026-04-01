# frozen_string_literal: true

require_relative '../../ui/text_utils'
require_relative '../../../../../shared/terminal/text_metrics'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Body rendering helpers for the translator screen.
          module TranslatorScreenComponentBodySupport
            BodyClusterLayout = Data.define(:text, :start_index, :end_index, :column_start, :column_end)
            BodyLineLayout = Data.define(:text, :start_index, :end_index, :clusters)

            private

            def body_lines(box, kind)
              height = body_height(box, kind)
              width = body_width(box)
              if body_text(kind).empty?
                return empty_source_lines(width, height) if kind == :source && show_input_cursor?

                return placeholder_lines(kind, width, height)
              end

              visible_layouts = visible_body_layouts_for_render(kind, width).first(height)
              rendered = visible_layouts.map { |line| render_body_layout_line(line, kind, width) }
              padded_lines(rendered, width, height)
            end

            def body_layouts(kind, width)
              build_text_layout(body_text(kind), width)
            end

            def body_text(kind)
              kind == :source ? translator_input_text : translator_output_text
            end

            def empty_source_lines(width, height)
              padded_lines([cursor_placeholder_line(width)].first(height), width, height)
            end

            def placeholder_lines(kind, width, height)
              text = kind == :source ? 'Type or paste text here.' : output_placeholder
              lines = [style_placeholder_line(text, width)]
              lines + Array.new([height - lines.length, 0].max) { empty_body_line(width) }
            end

            def output_placeholder
              translator_status == :error ? status_message : 'Translation appears here.'
            end

            def padded_lines(lines, width, height)
              padded = Array(lines).map { |line| pad_body_line(line, width) }
              padded + Array.new([height - padded.length, 0].max) { empty_body_line(width) }
            end

            def footer_text
              'Drag to select text. Right-click for Copy to Clipboard or Paste from Clipboard.'
            end

            def status_message
              return translator_message unless translator_message.empty?

              translator_status == :error ? 'Translation failed.' : 'Choose languages, then type on the left.'
            end

            def show_input_cursor?
              current_mode == :translator && translator_focus == :input
            end

            def cursor_placeholder_line(width)
              prompt_width = [width - 1, 1].max
              prompt = Shoko::Shared::Terminal::TextMetrics.truncate_to('Type or paste text here.', prompt_width)
              cursor = "#{cursor_bg}#{cursor_fg} #{reset}#{panel_muted_fg}"
              "#{cursor}#{prompt}#{reset}"
            end

            def style_placeholder_line(text, width)
              content = Shoko::Shared::Terminal::TextMetrics.truncate_to(text.to_s, width)
              "#{panel_muted_fg}#{content}#{reset}"
            end

            def render_body_layout_line(line, kind, width)
              selection = selection_for_kind(kind)
              cursor_index = source_cursor_index_for(kind, selection)
              return style_empty_body_line(cursor_index) if line.clusters.empty?

              rendered = line.clusters.each_with_object(+'') do |cluster, buffer|
                buffer << styled_cluster_text(cluster, selection, cursor_index)
              end
              if cursor_index && cursor_index == line.end_index && line.clusters.last.column_end < width
                rendered << styled_cursor_cell
              end
              rendered
            end

            def style_empty_body_line(cursor_index)
              return '' unless cursor_index

              styled_cursor_cell
            end

            def styled_cluster_text(cluster, selection, cursor_index)
              style = if cursor_index && cursor_covers_cluster?(cursor_index, cluster)
                        "#{cursor_bg}#{cursor_fg}"
                      elsif selection && cluster_selected?(cluster, selection)
                        "#{selection_bg}#{selection_fg}"
                      else
                        panel_text_fg
                      end
              "#{style}#{cluster.text}#{reset}"
            end

            def styled_cursor_cell
              "#{cursor_bg}#{cursor_fg} #{reset}"
            end

            def selection_for_kind(kind)
              selection = translator_selection
              return nil unless selection && selection[:pane].to_sym == kind

              start_index, end_index = selection_bounds(selection)
              return nil unless end_index > start_index

              {
                start_index: start_index,
                end_index: end_index,
              }
            end

            def selection_bounds(selection)
              start_index = selection[:start_index].to_i
              end_index = selection[:end_index].to_i
              start_index <= end_index ? [start_index, end_index] : [end_index, start_index]
            end

            def source_cursor_index_for(kind, selection)
              return nil unless kind == :source && show_input_cursor?
              return nil if selection

              translator_input_cursor.clamp(0, translator_input_text.length)
            end

            def cursor_covers_cluster?(cursor_index, cluster)
              cursor_index >= cluster.start_index && cursor_index < cluster.end_index
            end

            def cluster_selected?(cluster, selection)
              cluster.start_index < selection[:end_index] && cluster.end_index > selection[:start_index]
            end

            def build_text_layout(text, width)
              state = text_layout_state(width)
              text.to_s.each_grapheme_cluster do |cluster|
                process_text_layout_cluster(state, cluster)
              end
              finalize_text_layout(state)
            end

            def visible_body_layouts_for_render(kind, width)
              layouts = body_layouts(kind, width).dup
              return layouts unless needs_cursor_overflow_line?(kind, layouts, width)

              cursor_index = translator_input_cursor.clamp(0, translator_input_text.length)
              layouts << build_line_layout('', cursor_index, cursor_index, [])
            end

            def build_line_layout(text, start_index, end_index, clusters)
              BodyLineLayout.new(
                text: text.dup,
                start_index: start_index,
                end_index: end_index,
                clusters: clusters.dup
              )
            end

            def text_layout_state(width)
              {
                visible_width: [width.to_i, 1].max,
                codepoint_index: 0,
                line_start_index: 0,
                line_width: 0,
                line_text: +'',
                line_clusters: [],
                lines: [],
              }
            end

            def process_text_layout_cluster(state, cluster)
              return process_newline_cluster(state, cluster) if cluster == "\n"

              cluster_width = cluster_display_width(cluster)
              wrap_text_layout_line(state) if needs_text_layout_wrap?(state, cluster_width)
              append_text_layout_cluster(state, cluster, cluster_width)
            end

            def process_newline_cluster(state, cluster)
              push_text_layout_line(state)
              state[:codepoint_index] += cluster.length
              reset_text_layout_line(state)
            end

            def needs_text_layout_wrap?(state, cluster_width)
              state[:line_clusters].any? && state[:line_width] + cluster_width > state[:visible_width]
            end

            def wrap_text_layout_line(state)
              push_text_layout_line(state)
              reset_text_layout_line(state)
            end

            def append_text_layout_cluster(state, cluster, cluster_width)
              cluster_start = state[:codepoint_index]
              state[:codepoint_index] += cluster.length
              state[:line_clusters] << BodyClusterLayout.new(
                text: cluster,
                start_index: cluster_start,
                end_index: state[:codepoint_index],
                column_start: state[:line_width],
                column_end: state[:line_width] + cluster_width
              )
              state[:line_width] += cluster_width
              state[:line_text] << cluster
            end

            def finalize_text_layout(state)
              push_text_layout_line(state)
              state[:lines]
            end

            def push_text_layout_line(state)
              state[:lines] << build_line_layout(
                state[:line_text],
                state[:line_start_index],
                state[:codepoint_index],
                state[:line_clusters]
              )
            end

            def reset_text_layout_line(state)
              state[:line_start_index] = state[:codepoint_index]
              state[:line_width] = 0
              state[:line_text] = +''
              state[:line_clusters] = []
            end

            def cluster_display_width(cluster)
              [Shoko::Shared::Terminal::TextMetrics.display_width_for(cluster), 1].max
            end

            def needs_cursor_overflow_line?(kind, layouts, width)
              return false unless kind == :source && show_input_cursor? && selection_for_kind(:source).nil?

              cursor_index = translator_input_cursor.clamp(0, translator_input_text.length)
              last_line = layouts.last || build_line_layout('', 0, 0, [])
              cursor_index == last_line.end_index && last_line.clusters.last&.column_end.to_i >= width
            end
          end
        end
      end
    end
  end
end
