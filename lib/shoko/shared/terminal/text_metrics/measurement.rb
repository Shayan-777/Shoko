# frozen_string_literal: true

module Shoko
  module Shared
    module Terminal
      module TextMetrics
        # Visible-length and cell-data measurement helpers.
        module Measurement
          def visible_length(text)
            source = text.to_s
            cached_visible_length(source) { measured_visible_length(source) }
          end

          def cell_data_for(text)
            expanded = expand_tabs(text.to_s)
            cells = []
            char_index = 0
            screen_x = 0

            expanded.each_grapheme_cluster do |cluster|
              char_index, screen_x = append_cell_data(cells, cluster, char_index, screen_x)
            end

            cells
          end

          def strip_ansi(text)
            text.to_s.gsub(ANSI_REGEX, '')
          end

          def display_width_for(cluster)
            return TAB_SIZE if cluster == "\t"
            return 0 if cluster == "\u00AD"

            width = DISPLAY_WIDTH.call(cluster)
            width = 1 if width <= 0 && !cluster.empty?
            width
          rescue Shoko::Error
            cluster.length
          end

          def expand_tabs(text, tab_size: TAB_SIZE)
            column = 0
            buffer = +''

            text.to_s.each_grapheme_cluster do |cluster|
              if cluster == "\t"
                spaces = tab_size - (column % tab_size)
                buffer << (' ' * spaces)
                column += spaces
              else
                buffer << cluster
                column += display_width_for(cluster)
              end
            end

            buffer
          end

          private

          def measured_visible_length(source)
            stripped = strip_ansi(source)
            return visible_length_ascii(stripped) if ascii_fast_path_enabled? && stripped.ascii_only?

            expanded = expand_tabs(stripped)
            expanded.each_grapheme_cluster.sum { |cluster| display_width_for(cluster) }
          end

          def append_cell_data(cells, cluster, char_index, screen_x)
            grapheme_length = cluster.length
            display_width = display_width_for(cluster)

            cells << {
              cluster: cluster,
              char_start: char_index,
              char_end: char_index + grapheme_length,
              display_width: display_width,
              screen_x: screen_x,
            }

            [char_index + grapheme_length, screen_x + display_width]
          end

          def visible_length_ascii(text)
            return text.bytesize unless text.include?("\t")

            width = 0
            column = 0

            text.each_byte do |byte|
              if byte == 9
                spaces = TAB_SIZE - (column % TAB_SIZE)
                width += spaces
                column += spaces
              else
                width += 1
                column += 1
              end
            end

            width
          end

          def fast_ascii_truncate_candidate?(str)
            return false unless str.ascii_only?
            return false if str.include?("\e")

            !(str.include?("\t") || str.include?("\n") || str.include?("\r"))
          end
        end
      end
    end
  end
end
