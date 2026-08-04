# frozen_string_literal: true

require 'shoko/shared/hash_normalizer'
require_relative 'ui/backdrop_cell_map'
require_relative 'base_component'
require 'shoko/shared/terminal/text_metrics'
require 'shoko/core/models/selection_anchor'
require 'shoko/adapters/support/key_definitions'

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

          attr_reader :visible, :x, :y, :width, :height

          def initialize(selection_range, coordinate_service:, reader_state_reader: nil,
                         reader_session_mutator: nil, available_actions: nil, **options)
            super()
            @reader_state_reader = reader_state_reader
            @reader_session_mutator = reader_session_mutator
            configure_dependencies(coordinate_service, options)

            unless selection_available?(selection_range)
              hide_menu!
              return
            end

            build_menu_items(available_actions)
            if @items.empty?
              hide_menu!
              return
            end

            apply_popup_position(anchor_position: options[:anchor_position])
          end

          def do_render(surface, bounds)
            return unless @visible

            @height.times do |row_offset|
              render_menu_row(surface, bounds, row_offset)
            end
          end

          def handle_key(key)
            return nil unless @visible

            if Shoko::Adapters::Support::KeyDefinitions::NAVIGATION[:up].include?(key)
              move_selection(-1)
              { type: :selection_change }
            elsif Shoko::Adapters::Support::KeyDefinitions::NAVIGATION[:down].include?(key)
              move_selection(1)
              { type: :selection_change }
            elsif Shoko::Adapters::Support::KeyDefinitions::ACTIONS[:confirm].include?(key)
              execute_selected_action
            elsif Shoko::Adapters::Support::KeyDefinitions::ACTIONS[:cancel].include?(key)
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

            write_selection(clicked_index)
            execute_selected_action(clicked_index)
          end

          def handle_hover(hover_x, hover_y)
            return nil unless @visible && contains?(hover_x, hover_y)

            hovered_index = menu_index_for_row(hover_y)
            return nil unless hovered_index
            return nil if hovered_index == selected_index

            write_selection(hovered_index)
            { type: :selection_change }
          end

          def hide
            @visible = false
          end

          def contains?(column, row)
            bounds = Shoko::Adapters::Ui::Components::Rect.new(x: @x, y: @y, width: @width, height: @height)
            @coordinate_service.within_bounds?(column, row, bounds)
          end

          # Selection cursor is observable reader view-state; the component reads
          # it each render and writes changes back through the session mutator.
          def selected_index
            value = @reader_state_reader&.popup_menu_selected.to_i
            return 0 if @items.nil? || @items.empty?

            value.clamp(0, @items.length - 1)
          end

          private

          def write_selection(index)
            @reader_session_mutator&.update_reader(popup_menu_selected: index)
          end

          def configure_dependencies(coordinate_service, options)
            @coordinate_service = coordinate_service
            @popup_position_service = options[:popup_position_service]
            @clipboard_service = options[:clipboard_service]
            @rendered_lines = options.fetch(:rendered_lines, {}) || {}
            @backdrop_cells = Ui::BackdropCellMap.new(rendered_lines: @rendered_lines)
            @dictionary_enabled = options.fetch(:dictionary_enabled, false)
          end

          def selection_available?(selection_range)
            @selection_range = @coordinate_service.normalize_selection_range(selection_range, @rendered_lines)
            @backdrop_cells.update_rendered_lines(@rendered_lines)
            !@selection_range.nil?
          end

          def hide_menu!
            @visible = false
          end

          def build_menu_items(available_actions)
            @available_actions = available_actions || default_actions
            @items = @available_actions.map { |action| action[:label] }
            @visible = true
            @width = calculate_width
            @height = calculate_height
          end

          def default_actions
            actions = [popup_action('Create Annotation', :create_annotation)]
            actions << popup_action('Copy to Clipboard', :copy_to_clipboard) if @clipboard_service&.available?
            actions << popup_action('Look Up', :lookup) if @dictionary_enabled
            actions << popup_action('Translate', :translate)
            actions
          end

          def popup_action(label, action)
            {
              label: label,
              action: action,
            }
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

            write_selection((selected_index + direction) % @items.length)
          end

          def execute_selected_action(index = selected_index)
            action = @available_actions[index]
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

          def menu_index_for_row(row)
            item_index = row - @y - TOP_TEXT_PADDING
            return nil unless item_index >= 0 && item_index < @items.length

            item_index
          end

          def apply_popup_position(anchor_position:)
            position = popup_position_for(anchor_position: anchor_position)
            @x = position[:x]
            @y = position[:y]
          end

          def popup_position_for(anchor_position:)
            return explicit_anchor_popup_position(anchor_position) if anchor_position

            popup_anchor_position(@selection_range[:end])
          end

          def explicit_anchor_popup_position(anchor_position)
            anchor = normalize_anchor_position(anchor_position)
            calculate_popup_position(x_pos: anchor[:x], y_pos: anchor[:y])
          end

          def popup_anchor_position(anchor_hash)
            anchor = Shoko::Core::Models::SelectionAnchor.from(anchor_hash)
            geometry = geometry_for_anchor(anchor)
            return { x: 1, y: 1 } unless geometry

            calculate_popup_position(x_pos: anchor_column_position(anchor, geometry), y_pos: geometry.row)
          end

          def anchor_column_position(anchor, geometry)
            return geometry.column_origin + geometry.visible_width if anchor.cell_index >= geometry.cells.length

            geometry.column_origin + geometry.cells[anchor.cell_index].screen_x
          end

          def normalize_anchor_position(anchor)
            normalized = Shoko::Shared::HashNormalizer.symbolize_keys(anchor)
            {
              x: (normalized[:x] || 1).to_i,
              y: (normalized[:y] || 1).to_i,
            }
          end

          def geometry_for_anchor(anchor)
            return nil unless anchor && @rendered_lines

            entry = @rendered_lines[anchor.geometry_key]
            entry && entry[:geometry]
          end

          def calculate_popup_position(x_pos:, y_pos:)
            anchor = { x: x_pos, y: y_pos }
            return popup_position_from_service(anchor) if @popup_position_service
            return @coordinate_service.calculate_popup_position(anchor, @width, @height) if @coordinate_service

            { x: 1, y: 1 }
          end

          def popup_position_from_service(anchor)
            @popup_position_service.calculate_popup_position(anchor, @width, @height)
          end

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

            cell_map = @backdrop_cells.cells_for_row(row_index)
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
        end
      end
    end
  end
end
