# frozen_string_literal: true

require_relative 'base_component'
require_relative 'ui/box_drawer'
require_relative 'ui/overlay_layout'
require_relative 'annotations_overlay/list_renderer'
require_relative '../../../../shared/key_definitions'

module Shoko
  module Adapters::Output::Ui::Components
    # Centered overlay listing annotations above the reading surface.
    class AnnotationsOverlayComponent < BaseComponent
      include Adapters::Output::Ui::Constants::Ui
      include Ui::BoxDrawer

      def initialize(state, dependencies: nil)
        super()
        @state = state
        @dependencies = dependencies
        @reader_state_reader = nil
        @visible = true
        @selected_index = (reader_state_reader&.sidebar_annotations_selected || 0).to_i
        @overlay_sizing = Ui::OverlaySizing.new(
          width_ratio: 0.6,
          width_padding: 8,
          min_width: 48,
          height_ratio: 0.5,
          height_padding: 6,
          min_height: 12
        )
      end

      def visible?
        @visible
      end

      def hide
        @visible = false
      end

      def selected_index=(index)
        @selected_index = index.to_i
      end

      def handle_key(key)
        entries = annotations
        return { type: :close } if close_when_empty?(entries, key)

        navigation_action(key) || selection_action(key) || close_action(key)
      end

      def current_annotation
        entries = annotations
        entries.empty? ? nil : entries[@selected_index]
      end

      def scroll_up
        move_selection(-1)
      end

      def scroll_down
        move_selection(1)
      end

      def cancel
        { type: :close }
      end

      def render(surface, bounds)
        do_render(surface, bounds)
      end

      def do_render(surface, bounds)
        return unless @visible

        entries = annotations
        layout = overlay_layout(bounds)

        layout.fill_background(surface, bounds, background: POPUP_BG_DEFAULT)
        draw_box(surface, bounds, layout.origin_y, layout.origin_x, layout.height, layout.width, label: 'Annotations')
        render_context = AnnotationsOverlay::ListRenderer::RenderContext.new(
          surface: surface,
          bounds: bounds,
          layout: layout,
          entries: entries,
          selected_index: @selected_index
        )
        list_renderer.render(render_context)
        draw_footer(surface, bounds, layout)
      end

      private

      def annotations
        @annotations = (reader_state_reader&.annotations || []).map { |ann| symbolize_keys(ann) }
        clamp_selection!
        @annotations
      end

      def reader_state_reader
        return @reader_state_reader if @reader_state_reader

        @reader_state_reader = @dependencies&.reader_state_reader || @state
      end

      def clamp_selection!
        count = @annotations.length
        @selected_index = if count.zero?
                            0
                          else
                            @selected_index.clamp(0, count - 1)
                          end
      end

      def move_selection(delta)
        entries = annotations
        return if entries.empty?

        new_index = (@selected_index + delta).clamp(0, entries.length - 1)
        return if new_index == @selected_index

        @selected_index = new_index
        { type: :selection_change, index: @selected_index }
      end

      def draw_footer(surface, bounds, layout)
        hint = "#{COLOR_TEXT_DIM}Use ↑/↓ to navigate • Enter to open#{Terminal::ANSI::RESET}"
        surface.write(bounds, layout.origin_y + layout.height - 2, layout.origin_x + 2, hint)
      end

      def calculate_width(total_width)
        @overlay_sizing.width_for(total_width)
      end

      def calculate_height(total_height)
        @overlay_sizing.height_for(total_height)
      end

      def up_key?(key)
        Shared::KeyDefinitions::NAVIGATION[:up].include?(key)
      end

      def down_key?(key)
        Shared::KeyDefinitions::NAVIGATION[:down].include?(key)
      end

      def confirm_key?(key)
        Shared::KeyDefinitions::ACTIONS[:confirm].include?(key)
      end

      def cancel_key?(key)
        Shared::KeyDefinitions::ACTIONS[:cancel].include?(key)
      end

      def edit_key?(key)
        %w[e E].include?(key)
      end

      def delete_key?(key)
        key == 'd'
      end

      def close_when_empty?(entries, key)
        entries.empty? && cancel_key?(key)
      end

      def navigation_action(key)
        return move_selection(-1) if up_key?(key)

        move_selection(1) if down_key?(key)
      end

      def selection_action(key)
        annotation = current_annotation
        return nil unless annotation

        return { type: :open, annotation: annotation } if confirm_key?(key)
        return { type: :edit, annotation: annotation } if edit_key?(key)

        { type: :delete, annotation: annotation } if delete_key?(key)
      end

      def close_action(key)
        { type: :close } if cancel_key?(key)
      end

      def overlay_layout(bounds)
        width = calculate_width(bounds.width)
        height = calculate_height(bounds.height)
        Ui::OverlayLayout.centered(bounds, width: width, height: height)
      end

      def list_renderer
        @list_renderer ||= AnnotationsOverlay::ListRenderer.new
      end

      def symbolize_keys(annotation)
        return annotation unless annotation.is_a?(Hash)

        annotation.transform_keys do |key|
          key.is_a?(String) ? key.to_sym : key
        end
      end
    end
  end
end
