# frozen_string_literal: true

require_relative 'base_component'
require_relative '../../../shared/terminal/text_metrics'
require_relative '../../../core/models/selection_anchor'
require_relative '../../../shared/key_definitions'
require_relative 'enhanced_popup_menu/positioning_helpers'
require_relative 'enhanced_popup_menu/render_helpers'

module Shoko
  module Adapters
    module Ui
      module Components
        # Enhanced popup menu that uses the coordinate service for consistent positioning
        # and integrates with the clipboard service for reliable copy functionality.
        class EnhancedPopupMenu < BaseComponent
          include Adapters::Ui::Constants::Ui
          include EnhancedPopupMenuPositioningHelpers
          include EnhancedPopupMenuRenderHelpers

          LEFT_TEXT_MARGIN = 1
          RIGHT_TEXT_PADDING = 2
          TOP_TEXT_PADDING = 1
          BOTTOM_TEXT_PADDING = 1

          attr_reader :visible, :selected_index, :x, :y, :width, :height

          def initialize(selection_range, coordinate_service:, available_actions: nil, **options)
            super()
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

          def contains?(column, row)
            bounds = Shoko::Adapters::Ui::Components::Rect.new(x: @x, y: @y, width: @width, height: @height)
            @coordinate_service.within_bounds?(column, row, bounds)
          end

          private

          def configure_dependencies(coordinate_service, options)
            @coordinate_service = coordinate_service
            @popup_position_service = options[:popup_position_service]
            @clipboard_service = options[:clipboard_service]
            @rendered_lines = options.fetch(:rendered_lines, {}) || {}
            @dictionary_enabled = options.fetch(:dictionary_enabled, false)
          end

          def selection_available?(selection_range)
            @selection_range = @coordinate_service.normalize_selection_range(selection_range, @rendered_lines)
            @backdrop_rows_key = nil
            @backdrop_rows = {}
            !@selection_range.nil?
          end

          def hide_menu!
            @visible = false
          end

          def build_menu_items(available_actions)
            @available_actions = available_actions || default_actions
            @items = @available_actions.map { |action| action[:label] }
            @selected_index = 0
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

          def menu_index_for_row(row)
            item_index = row - @y - TOP_TEXT_PADDING
            return nil unless item_index >= 0 && item_index < @items.length

            item_index
          end
        end
      end
    end
  end
end
