# frozen_string_literal: true

require_relative 'base_component'
require_relative '../../../shared/terminal/text_metrics'
require_relative '../../../core/models/selection_anchor'
require_relative '../../../shared/key_definitions'

module Shoko
  module Adapters
    module Ui
      module Components
        # Enhanced popup menu that uses the coordinate service for consistent positioning
        # and integrates with the clipboard service for reliable copy functionality.
        class EnhancedPopupMenu < BaseComponent
          include Adapters::Ui::Constants::Ui

          LEFT_TEXT_MARGIN = 1
          RIGHT_TEXT_PADDING = 2
          TOP_TEXT_PADDING = 1
          BOTTOM_TEXT_PADDING = 1

          attr_reader :visible, :selected_index, :x, :y, :width, :height

          def initialize(selection_range, available_actions = nil, coordinate_service = nil,
                         popup_position_service = nil, clipboard_service = nil,
                         rendered_lines = nil, dictionary_enabled: false, anchor_position: nil)
            super()
            @coordinate_service = coordinate_service
            @popup_position_service = popup_position_service
            @clipboard_service = clipboard_service
            @rendered_lines = rendered_lines || {}
            @dictionary_enabled = dictionary_enabled

            @selection_range = @coordinate_service.normalize_selection_range(selection_range, @rendered_lines)
            @backdrop_rows_key = nil
            @backdrop_rows = {}

            unless @selection_range
              @visible = false
              return
            end

            @available_actions = available_actions || default_actions
            @items = @available_actions.map { |action| action[:label] }
            @selected_index = 0
            @visible = true
            @width = calculate_width
            @height = calculate_height

            # Ensure we have at least one item before proceeding
            unless @items.any?
              @visible = false
              return
            end

            # Calculate popup position. Context-click can supply an explicit anchor.
            position = if anchor_position
                         anchor = normalize_anchor_position(anchor_position)
                         calculate_popup_position(x: anchor[:x], y: anchor[:y])
                       else
                         popup_anchor_position(@selection_range[:end])
                       end
            @x = position[:x]
            @y = position[:y]
          end

          def do_render(surface, bounds)
            return unless @visible

            @height.times do |row_offset|
              render_menu_row(surface, bounds, row_offset)
            end
          end

          def handle_key(key)
            return nil unless @visible

            if Shared::KeyDefinitions::NAVIGATION[:up].include?(key)
              move_selection(-1)
              { type: :selection_change }
            elsif Shared::KeyDefinitions::NAVIGATION[:down].include?(key)
              move_selection(1)
              { type: :selection_change }
            elsif Shared::KeyDefinitions::ACTIONS[:confirm].include?(key)
              execute_selected_action
            elsif Shared::KeyDefinitions::ACTIONS[:cancel].include?(key)
              { type: :cancel }
            end
          end

          # Align with BaseComponent naming; delegate to existing logic
          def handle_input(key)
            handle_key(key)
          end

          def handle_click(click_x, click_y)
            return nil unless @visible && contains?(click_x, click_y)

            clicked_index = menu_index_for_row(click_y)
            return nil unless clicked_index

            @selected_index = clicked_index
            execute_selected_action
          end

          def handle_hover(hover_x, hover_y)
            return nil unless @visible && contains?(hover_x, hover_y)

            hovered_index = menu_index_for_row(hover_y)
            return nil unless hovered_index
            return nil if hovered_index == @selected_index

            @selected_index = hovered_index
            { type: :selection_change }
          end

          def hide
            @visible = false
          end

          def contains?(col, row)
            bounds = Shoko::Adapters::Ui::Components::Rect.new(x: @x, y: @y, width: @width, height: @height)
            @coordinate_service.within_bounds?(col, row, bounds)
          end

          private

          def default_actions
            actions = []

            # Always offer annotation creation
            actions << {
              label: 'Create Annotation',
              action: :create_annotation,
            }

            # Only offer clipboard if available
            if @clipboard_service&.available?
              actions << {
                label: 'Copy to Clipboard',
                action: :copy_to_clipboard,
              }
            end

            # Dictionary lookup
            if @dictionary_enabled
              actions << {
                label: 'Look Up',
                action: :lookup,
              }
            end

            actions
          end

          def calculate_width
            max_label_width = @items.map do |item|
              Shoko::Shared::Terminal::TextMetrics.visible_length(item)
            end.max || 0
            max_label_width + LEFT_TEXT_MARGIN + RIGHT_TEXT_PADDING
          end

          def calculate_height
            @items.length + TOP_TEXT_PADDING + BOTTOM_TEXT_PADDING
          end

          def move_selection(direction)
            return if @items.empty?

            @selected_index = (@selected_index + direction) % @items.length
          end

          def execute_selected_action
            action = @available_actions[@selected_index]
            return { type: :cancel } unless action

            {
              type: :action,
              action: action[:action],
              data: {
                selection_range: @selection_range,
                action_config: action,
              },
            }
          end

          def popup_anchor_position(anchor_hash)
            anchor = Shoko::Core::Models::SelectionAnchor.from(anchor_hash)
            geometry = geometry_for_anchor(anchor)
            return { x: 1, y: 1 } unless geometry

            x = if anchor.cell_index >= geometry.cells.length
                  geometry.column_origin + geometry.visible_width
                else
                  cell = geometry.cells[anchor.cell_index]
                  geometry.column_origin + cell.screen_x
                end
            y = geometry.row

            calculate_popup_position(x: x, y: y)
          end

          def normalize_anchor_position(anchor)
            {
              x: (anchor[:x] || anchor['x'] || 1).to_i,
              y: (anchor[:y] || anchor['y'] || 1).to_i,
            }
          end

          def geometry_for_anchor(anchor)
            return nil unless anchor

            return nil unless @rendered_lines

            entry = @rendered_lines[anchor.geometry_key]
            (entry && entry[:geometry]) || nil
          end

          def calculate_popup_position(x:, y:)
            if @popup_position_service
              return @popup_position_service.calculate_popup_position({ x: x, y: y }, @width, @height)
            end

            return @coordinate_service.calculate_popup_position({ x: x, y: y }, @width, @height) if @coordinate_service

            { x: 1, y: 1 }
          end

          def render_menu_row(surface, bounds, row_offset)
            item_index = row_offset - TOP_TEXT_PADDING
            item = (item_index >= 0 && item_index < @items.length) ? @items[item_index] : nil
            item_y = @y + row_offset
            is_selected = (item_index == @selected_index)
            surface.write_abs(bounds, item_y, @x, compose_row(item: item, row: item_y, selected: is_selected))
          end

          def backdrop_line_for_row(row)
            return '' if @width <= 0

            cell_map = backdrop_cells_for_row(row)
            (@x...(@x + @width)).map do |col|
              value = cell_map[col]
              next ' ' if value == :continuation

              attenuate_backdrop_char(value, col: col, row: row)
            end.join
          end

          def attenuate_backdrop_char(value, col:, row:)
            char = value.to_s
            return ' ' if char.empty? || char == ' '

            char
          end

          def compose_row(item:, row:, selected:)
            bg = selected ? TOOLTIP_BG_SELECTED : TOOLTIP_BG_DEFAULT
            label_fg = selected ? TOOLTIP_FG_SELECTED : TOOLTIP_FG_DEFAULT
            glass_fg = selected ? TOOLTIP_GLASS_FG_SELECTED : TOOLTIP_GLASS_FG_DEFAULT

            backdrop_chars = backdrop_line_for_row(row).each_grapheme_cluster.to_a
            backdrop_chars.fill(' ', backdrop_chars.length...@width)

            label_segment = label_segment_for(item).each_grapheme_cluster.to_a
            segment_width = [label_segment.length, @width].min

            output = +"#{bg}"
            current_fg = nil

            @width.times do |index|
              use_label = index < segment_width
              fg = use_label ? label_fg : glass_fg
              output << fg if fg != current_fg
              current_fg = fg
              output << (use_label ? label_segment[index] : (backdrop_chars[index] || ' '))
            end

            output << Shoko::Shared::Terminal::Ansi::RESET
            output
          end

          def label_segment_for(item)
            return '' unless item

            max_label_width = [@width - LEFT_TEXT_MARGIN - RIGHT_TEXT_PADDING, 0].max
            line_text = Shoko::Shared::Terminal::TextMetrics.truncate_to(item.to_s, max_label_width)
            (' ' * LEFT_TEXT_MARGIN) + line_text + (' ' * RIGHT_TEXT_PADDING)
          end

          def menu_index_for_row(row)
            row_offset = row - @y
            item_index = row_offset - TOP_TEXT_PADDING
            return nil unless item_index >= 0 && item_index < @items.length

            item_index
          end

          def backdrop_cells_for_row(row)
            cache = backdrop_row_cache
            return cache[row] if cache.key?(row)

            cells = {}
            geometries_for_row(row).each do |geometry|
              Array(geometry.cells).each do |cell|
                width = cell.display_width.to_i
                next if width <= 0

                abs_col = geometry.column_origin.to_i + cell.screen_x.to_i
                cluster = cell.cluster.to_s
                cells[abs_col] = cluster.empty? ? ' ' : cluster
                1.upto(width - 1) { |delta| cells[abs_col + delta] = :continuation }
              end
            end

            cache[row] = cells
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
