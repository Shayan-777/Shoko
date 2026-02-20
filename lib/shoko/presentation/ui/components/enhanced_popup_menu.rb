# frozen_string_literal: true

require_relative 'base_component'
require_relative '../../../adapters/output/terminal/text_metrics'
require_relative '../../../core/models/selection_anchor'
require_relative '../../../shared/key_definitions'

module Shoko
  module Presentation::Ui::Components
    # Enhanced popup menu that uses the coordinate service for consistent positioning
    # and integrates with the clipboard service for reliable copy functionality.
    class EnhancedPopupMenu < BaseComponent
      include Presentation::Ui::Constants::Ui

      attr_reader :visible, :selected_index, :x, :y, :width, :height

      def initialize(selection_range, available_actions = nil, coordinate_service = nil,
                     popup_position_service = nil, clipboard_service = nil,
                     rendered_lines = nil, dictionary_enabled: false)
        super()
        @coordinate_service = coordinate_service
        @popup_position_service = popup_position_service
        @clipboard_service = clipboard_service
        @rendered_lines = rendered_lines || {}
        @dictionary_enabled = dictionary_enabled

        @selection_range = @coordinate_service.normalize_selection_range(selection_range, @rendered_lines)

        unless @selection_range
          @visible = false
          return
        end

        @available_actions = available_actions || default_actions
        @items = @available_actions.map { |action| action[:label] }
        @selected_index = 0
        @visible = true
        @width = calculate_width
        @height = @items.length

        # Ensure we have at least one item before proceeding
        unless @items.any?
          @visible = false
          return
        end

        # Calculate optimal position using coordinate service
        position = popup_anchor_position(@selection_range[:end])
        @x = position[:x]
        @y = position[:y]
      end

      def do_render(surface, bounds)
        return unless @visible

        @items.each_with_index do |item, i|
          render_menu_item(surface, bounds, item, i)
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

        clicked_index = click_y - @y
        return nil unless clicked_index >= 0 && clicked_index < @items.length

        @selected_index = clicked_index
        execute_selected_action
      end

      def hide
        @visible = false
      end

      def contains?(col, row)
        bounds = Shoko::Presentation::Ui::Components::Rect.new(x: @x, y: @y, width: @width, height: @height)
        @coordinate_service.within_bounds?(col, row, bounds)
      end

      private

      def default_actions
        actions = []

        # Always offer annotation creation
        actions << {
          label: 'Create Annotation',
          action: :create_annotation,
          icon: "\u{F14E9}",
        }

        # Only offer clipboard if available
        if @clipboard_service&.available?
          actions << {
            label: 'Copy to Clipboard',
            action: :copy_to_clipboard,
            icon: "\u{F03FF}",
          }
        end

        # Dictionary lookup
        if @dictionary_enabled
          actions << {
            label: 'Look Up',
            action: :lookup,
            icon: "\u{F02D}",
          }
        end

        actions
      end

      def calculate_width
        max_label_width = @items.map do |item|
          Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(item)
        end.max || 0
        max_label_width + 6 # Padding for icon and spacing
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

      def geometry_for_anchor(anchor)
        return nil unless anchor

        return nil unless @rendered_lines

        entry = @rendered_lines[anchor.geometry_key]
        (entry && entry[:geometry]) || nil
      end

      def calculate_popup_position(x:, y:)
        if @popup_position_service&.respond_to?(:calculate_popup_position)
          return @popup_position_service.calculate_popup_position({ x: x, y: y }, @width, @height)
        end

        if @coordinate_service&.respond_to?(:calculate_popup_position)
          return @coordinate_service.calculate_popup_position({ x: x, y: y }, @width, @height)
        end

        { x: 1, y: 1 }
      end

      def render_menu_item(surface, bounds, item, index)
        item_y = @y + index
        is_selected = (index == @selected_index)
        action = @available_actions[index]

        # Colors
        bg = is_selected ? TOOLTIP_BG_SELECTED : TOOLTIP_BG_DEFAULT
        fg = is_selected ? TOOLTIP_FG_SELECTED : TOOLTIP_FG_DEFAULT

        # Background
        surface.write_abs(bounds, item_y, @x, "#{bg}#{' ' * @width}#{Terminal::ANSI::RESET}")

        # Content with icon
        indicator = is_selected ? '❯' : ' '
        icon = action[:icon] || ' '
        line_text = Shoko::Adapters::Output::Terminal::TextMetrics.pad_right("#{indicator}#{icon} #{item} ", @width)
        surface.write_abs(bounds, item_y, @x, "#{bg}#{fg}#{line_text}#{Terminal::ANSI::RESET}")
      end
    end
  end
end
