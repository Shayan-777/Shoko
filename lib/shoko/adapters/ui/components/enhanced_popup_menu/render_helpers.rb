# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        # Rendering/backdrop composition helpers for popup rows.
        module EnhancedPopupMenuRenderHelpers
          private

          def render_menu_row(surface, bounds, row_offset)
            item_index = row_offset - self.class::TOP_TEXT_PADDING
            row_index = @y + row_offset
            item = item_for_index(item_index)
            selected = (item_index == selected_index)
            row_text = compose_row(item: item, row_index: row_index, selected: selected)
            surface.write_abs(bounds, row_index, @x, row_text)
          end

          def item_for_index(item_index)
            return nil unless item_index >= 0 && item_index < @items.length

            @items[item_index]
          end

          def backdrop_line_for_row(row_index)
            return '' if @width <= 0

            cell_map = backdrop_cells_for_row(row_index)
            (@x...(@x + @width)).map do |column|
              value = cell_map[column]
              next ' ' if value == :continuation

              attenuate_backdrop_char(value)
            end.join
          end

          def attenuate_backdrop_char(value)
            char = value.to_s
            return ' ' if char.empty? || char == ' '

            char
          end

          def compose_row(item:, row_index:, selected:)
            palette = row_palette(selected)
            backdrop_chars = backdrop_characters_for_row(row_index)
            label_chars = label_segment_for(item).each_grapheme_cluster.to_a
            build_row_text(palette: palette, label_chars: label_chars, backdrop_chars: backdrop_chars)
          end

          def row_palette(selected)
            return selected_row_palette if selected

            default_row_palette
          end

          def selected_row_palette
            {
              bg: Shoko::Adapters::Ui::Constants::Ui::TOOLTIP_BG_SELECTED,
              label_fg: Shoko::Adapters::Ui::Constants::Ui::TOOLTIP_FG_SELECTED,
              glass_fg: Shoko::Adapters::Ui::Constants::Ui::TOOLTIP_GLASS_FG_SELECTED,
            }
          end

          def default_row_palette
            {
              bg: Shoko::Adapters::Ui::Constants::Ui::TOOLTIP_BG_DEFAULT,
              label_fg: Shoko::Adapters::Ui::Constants::Ui::TOOLTIP_FG_DEFAULT,
              glass_fg: Shoko::Adapters::Ui::Constants::Ui::TOOLTIP_GLASS_FG_DEFAULT,
            }
          end

          def backdrop_characters_for_row(row_index)
            chars = backdrop_line_for_row(row_index).each_grapheme_cluster.to_a
            chars.fill(' ', chars.length...@width)
          end

          def build_row_text(palette:, label_chars:, backdrop_chars:)
            label_width = [label_chars.length, @width].min
            output = String.new(palette[:bg])
            foreground = nil

            @width.times do |index|
              use_label = index < label_width
              color = use_label ? palette[:label_fg] : palette[:glass_fg]
              output << color if color != foreground
              foreground = color
              output << row_character_for_index(index, use_label, label_chars, backdrop_chars)
            end

            output << Shoko::Shared::Terminal::Ansi::RESET
          end

          def row_character_for_index(index, use_label, label_chars, backdrop_chars)
            row_character(index, use_label: use_label, label_chars: label_chars, backdrop_chars: backdrop_chars)
          end

          def row_character(index, use_label:, label_chars:, backdrop_chars:)
            return label_chars[index] if use_label

            backdrop_chars[index] || ' '
          end

          def label_segment_for(item)
            return '' unless item

            max_label_width = [@width - self.class::LEFT_TEXT_MARGIN - self.class::RIGHT_TEXT_PADDING, 0].max
            line_text = Shoko::Shared::Terminal::TextMetrics.truncate_to(item.to_s, max_label_width)
            (' ' * self.class::LEFT_TEXT_MARGIN) + line_text + (' ' * self.class::RIGHT_TEXT_PADDING)
          end

          def backdrop_cells_for_row(row)
            cache = backdrop_row_cache
            return cache[row] if cache.key?(row)

            cache[row] = build_backdrop_cells(row)
          end

          def build_backdrop_cells(row)
            geometries_for_row(row).each_with_object({}) do |geometry, cells|
              merge_geometry_cells(cells, geometry)
            end
          end

          def merge_geometry_cells(cells, geometry)
            Array(geometry.cells).each do |cell|
              merge_cell(cells, geometry, cell)
            end
          end

          def merge_cell(cells, geometry, cell)
            width = cell.display_width.to_i
            return if width <= 0

            absolute_column = geometry.column_origin.to_i + cell.screen_x.to_i
            cluster = cell.cluster.to_s
            cells[absolute_column] = cluster.empty? ? ' ' : cluster
            mark_continuation_cells(cells, absolute_column, width)
          end

          def mark_continuation_cells(cells, absolute_column, width)
            1.upto(width - 1) do |delta|
              cells[absolute_column + delta] = :continuation
            end
          end

          def backdrop_row_cache
            key = @rendered_lines.object_id
            return @backdrop_rows if @backdrop_rows_key == key

            @backdrop_rows_key = key
            @backdrop_rows = {}
          end

          def geometries_for_row(row)
            return [] unless @rendered_lines.is_a?(Hash)

            geometries = @rendered_lines.each_value.filter_map do |entry|
              geometry = entry && entry[:geometry]
              next unless geometry
              next unless geometry.row.to_i == row.to_i

              geometry
            end

            geometries.sort_by { |geometry| geometry.column_origin.to_i }
          end
        end
      end
    end
  end
end
