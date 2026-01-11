# frozen_string_literal: true

require 'ostruct'

require_relative 'reader_controller'
require_relative '../../adapters/input/annotations/mouse_handler.rb'
# Removed unused: ui/components/popup_menu
require_relative '../../adapters/output/ui/components/enhanced_popup_menu.rb'
require_relative '../../adapters/output/ui/components/tooltip_overlay_component.rb'

module Shoko
  module Application
    module Controllers
  # A Reader that supports mouse interactions for annotations.
  class MouseableReader < ReaderController
    SCROLL_WHEEL_STEP = 3

    def initialize(epub_path, config = nil, dependencies = nil)
      # Pass dependencies to parent ReaderController
      super

      # Resolve coordinate service (clipboard already resolved in parent)
      @coordinate_service = dependencies.resolve(:coordinate_service)

      @mouse_handler = Shoko::Adapters::Input::Annotations::MouseHandler.new
      @mouse_input_buffer = nil
      @sidebar_scroll_drag_active = false
      state.dispatch(Application::Actions::ClearPopupMenuAction.new)
      @selected_text = nil
      state.dispatch(Application::Actions::ClearSelectionAction.new)
      state.dispatch(Application::Actions::ClearRenderedLinesAction.new)
      refresh_annotations
    end

    def run
      terminal_service.enable_mouse
      super
    ensure
      terminal_service.disable_mouse
    end

    def read_input_keys(timeout: nil)
      key = terminal_service.read_input_with_mouse(timeout: timeout)
      return [] unless key

      keys = [key]
      while (extra = terminal_service.read_key)
        keys << extra
        break if keys.size > 10
      end

      filter_mouse_sequences(keys)
    end

    def filter_mouse_sequences(keys)
      remaining = []
      saw_mouse = false
      saw_mouse_prefix = false

      keys.each do |token|
        if @mouse_input_buffer
          @mouse_input_buffer << token
          if @mouse_handler.mouse_sequence?(@mouse_input_buffer)
            handle_mouse_input(@mouse_input_buffer)
            @mouse_input_buffer = nil
            saw_mouse = true
            next
          end

          if @mouse_handler.mouse_prefix?(@mouse_input_buffer)
            saw_mouse_prefix = true
            next
          end

          remaining << @mouse_input_buffer
          @mouse_input_buffer = nil
          next
        end

        if @mouse_handler.mouse_sequence?(token)
          handle_mouse_input(token)
          saw_mouse = true
          next
        end

        if @mouse_handler.mouse_prefix?(token)
          @mouse_input_buffer = String(token)
          saw_mouse_prefix = true
          next
        end

        if saw_mouse || saw_mouse_prefix
          next if token == 'q' || token == "\e"
        end

        remaining << token
      end

      remaining
    end

    def handle_mouse_input(input)
      event = @mouse_handler.parse_mouse_event(input)
      return unless event

      editor_overlay = Shoko::Application::Selectors::ReaderSelectors.annotation_editor_overlay(state)
      if editor_overlay.respond_to?(:visible?) && editor_overlay.visible? && event[:released]
        handle_annotation_editor_click(event)
        return
      end

      popup_menu = Shoko::Application::Selectors::ReaderSelectors.popup_menu(state)
      if popup_menu&.visible && event[:released]
        handle_popup_click(event)
        return
      end

      return if handle_sidebar_mouse(event)

      result = @mouse_handler.handle_event(event)
      return unless result

      case result[:type]
      when :selection_drag
        # Keep selection in state while dragging so overlay can render purely from state
        update_state_selection(@mouse_handler.selection_range)
        refresh_highlighting
      when :selection_end
        handle_selection_end
        draw_screen
      else
        draw_screen
      end
    end

    private

    def handle_sidebar_mouse(event)
      return false if @mouse_handler.selecting

      terminal_coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])
      height, width = terminal_service.size
      sidebar_bounds = render_coordinator.sidebar_bounds(width, height)
      return false unless sidebar_bounds
      sidebar_component = render_coordinator.sidebar_component
      return false unless sidebar_component

      if @sidebar_scroll_drag_active
        return handle_sidebar_scroll_drag(event, terminal_coords, sidebar_bounds, sidebar_component)
      end

      unless @coordinate_service.within_bounds?(
        terminal_coords[:x],
        terminal_coords[:y],
        sidebar_bounds
      )
        @mouse_handler.reset
        return false
      end

      if (delta = mouse_wheel_delta(event[:button]))
        return true if handle_sidebar_wheel(delta, terminal_coords, sidebar_bounds, sidebar_component)
      end

      if event[:button].zero? && !event[:released]
        return true if start_sidebar_scroll_drag(terminal_coords, sidebar_bounds, sidebar_component)
      end

      if event[:released] && event[:button].zero?
        tab = sidebar_component.tab_for_point(
          terminal_coords[:x],
          terminal_coords[:y],
          sidebar_bounds
        )
        if tab
          ui_controller.activate_sidebar_tab(tab)
          draw_screen
          @mouse_handler.reset
          return true
        end

        toc_item = sidebar_component.toc_entry_at(
          terminal_coords[:x],
          terminal_coords[:y],
          sidebar_bounds
        )
        if toc_item && ui_controller.respond_to?(:handle_sidebar_toc_click)
          ui_controller.handle_sidebar_toc_click(toc_item.full_index)
          draw_screen
        end
      end

      @mouse_handler.reset
      true
    end

    def mouse_wheel_delta(button)
      case button
      when 64
        -1
      when 65
        1
      end
    end

    def handle_sidebar_wheel(delta, terminal_coords, sidebar_bounds, sidebar_component)
      metrics = sidebar_component.toc_scroll_metrics(sidebar_bounds)
      return false unless metrics
      return false unless metrics.row_in_track?(terminal_coords[:y])

      indices = metrics.navigable_indices
      return false if indices.empty?

      current_full = metrics.selected_full_index || indices.first
      current_pos = metrics.nav_position_for(current_full)
      if current_pos.nil? && metrics.selected_visible_index
        fallback_full = metrics.visible_indices[metrics.selected_visible_index]
        current_pos = metrics.nav_position_for(fallback_full)
      end
      current_pos ||= 0

      step = SCROLL_WHEEL_STEP * delta
      target_pos = (current_pos + step).clamp(0, indices.length - 1)
      target_full = indices[target_pos]

      if ui_controller.respond_to?(:set_sidebar_toc_selected)
        ui_controller.set_sidebar_toc_selected(target_full)
      else
        state.dispatch(Application::Actions::UpdateSidebarAction.new(toc_selected: target_full))
      end
      draw_screen
      @mouse_handler.reset
      true
    end

    def start_sidebar_scroll_drag(terminal_coords, sidebar_bounds, sidebar_component)
      metrics = sidebar_component.toc_scroll_metrics(sidebar_bounds)
      return false unless metrics
      return false unless metrics.hit_scrollbar?(terminal_coords[:x], terminal_coords[:y])

      @sidebar_scroll_drag_active = true
      apply_sidebar_scroll_drag(metrics, terminal_coords[:y])
      draw_screen
      @mouse_handler.reset
      true
    end

    def handle_sidebar_scroll_drag(event, terminal_coords, sidebar_bounds, sidebar_component)
      if event[:released]
        @sidebar_scroll_drag_active = false
        @mouse_handler.reset
        return true
      end

      return true unless drag_motion?(event) || event[:button].zero?

      metrics = sidebar_component.toc_scroll_metrics(sidebar_bounds)
      return true unless metrics

      apply_sidebar_scroll_drag(metrics, terminal_coords[:y])
      draw_screen
      true
    end

    def drag_motion?(event)
      (event[:button] & 32) != 0
    end

    def apply_sidebar_scroll_drag(metrics, abs_row)
      full_index = metrics.full_index_for_abs_row(abs_row)
      return unless full_index

      if ui_controller.respond_to?(:set_sidebar_toc_selected)
        ui_controller.set_sidebar_toc_selected(full_index)
      else
        state.dispatch(Application::Actions::UpdateSidebarAction.new(toc_selected: full_index))
      end
    end

    def handle_popup_click(event)
      # Use coordinate service for consistent mouse-to-terminal conversion
      terminal_coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])

      popup_menu = Shoko::Application::Selectors::ReaderSelectors.popup_menu(state)
      item = popup_menu.handle_click(terminal_coords[:x], terminal_coords[:y])

      if item
        handle_popup_action(item)
      else
        state.dispatch(Application::Actions::ClearPopupMenuAction.new)
        @mouse_handler.reset
        state.dispatch(Application::Actions::ClearSelectionAction.new)
      end
      draw_screen
    end

    def handle_annotation_editor_click(event)
      coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])
      overlay = Shoko::Application::Selectors::ReaderSelectors.annotation_editor_overlay(state)
      return unless overlay

      result = overlay.handle_click(coords[:x], coords[:y])
      if result
        ui = dependencies.resolve(:ui_controller)
        if ui.respond_to?(:handle_annotation_editor_overlay_event, true)
          ui.send(:handle_annotation_editor_overlay_event, result)
        end
      end
      @mouse_handler.reset
    ensure
      draw_screen
    end

    def handle_selection_end
      update_state_selection(@mouse_handler.selection_range)
      sel = state.get(%i[reader selection])
      return unless sel

      @selected_text = extract_selected_text(sel)

      if @selected_text && !@selected_text.strip.empty?
        show_popup_menu
      else
        @mouse_handler.reset
        state.dispatch(Application::Actions::ClearSelectionAction.new)
      end
    end

    def show_popup_menu
      selection = Shoko::Application::Selectors::ReaderSelectors.selection(state)
      return unless selection

      # Use enhanced popup menu with coordinate service
      rendered = Shoko::Application::Selectors::ReaderSelectors.rendered_lines(state)
      popup_menu = Shoko::Adapters::Output::Ui::Components::EnhancedPopupMenu.new(selection, nil, @coordinate_service,
                                                     clipboard_service, rendered)
      state.dispatch(Application::Actions::UpdatePopupMenuAction.new(popup_menu))
      return unless popup_menu&.visible # Only proceed if menu was created successfully

      # Ensure popup menu has proper focus and state
      switch_mode(:popup_menu)

      # Force a complete redraw to ensure popup appears correctly
      draw_screen
    end

    # Clear any active text selection and hide popup
    def clear_selection!
      state.dispatch(Application::Actions::ClearPopupMenuAction.new)
      @mouse_handler&.reset
      state&.dispatch(Application::Actions::ClearSelectionAction.new)
    end

    # Old highlighting methods removed - now handled by TooltipOverlayComponent
    # This eliminates the direct terminal writes that bypassed the component system

    def refresh_annotations
      begin
        service = dependencies.resolve(:annotation_service)
        annotations = service.list_for_book(path)
      rescue StandardError
        annotations = []
      end
      state.dispatch(Application::Actions::UpdateAnnotationsAction.new(annotations))
    end

    def extract_selected_text(range)
      selection_service = dependencies.resolve(:selection_service)
      if selection_service.respond_to?(:extract_from_state)
        selection_service.extract_from_state(state, range)
      else
        rendered = Shoko::Application::Selectors::ReaderSelectors.rendered_lines(state)
        selection_service.extract_text(range, rendered)
      end
    end

    def update_state_selection(mouse_range)
      anchor_range = anchor_range_from_mouse(mouse_range)
      if anchor_range
        state.dispatch(Application::Actions::UpdateSelectionAction.new(anchor_range))
      else
        state.dispatch(Application::Actions::ClearSelectionAction.new)
      end
    end

    def anchor_range_from_mouse(mouse_range)
      return nil unless mouse_range

      rendered = Shoko::Application::Selectors::ReaderSelectors.rendered_lines(state)
      return nil if rendered.empty?

      start_anchor = @coordinate_service.anchor_from_point(mouse_range[:start], rendered, bias: :leading)
      end_anchor = @coordinate_service.anchor_from_point(mouse_range[:end], rendered, bias: :trailing)
      return nil unless start_anchor && end_anchor

      @coordinate_service.normalize_selection_range(
        { start: start_anchor.to_h, end: end_anchor.to_h }, rendered
      )
    end

    def copy_to_clipboard(text)
      ui = dependencies.resolve(:ui_controller)
      clipboard_service.copy_with_feedback(text) do |message|
        ui.set_message(message)
      rescue StandardError
        # best-effort
      end
    rescue Adapters::Output::Clipboard::ClipboardService::ClipboardError => e
      begin
        ui.set_message("Copy failed: #{e.message}")
      rescue StandardError
        # ignore
      end
      false
    end

    # Column helpers moved to CoordinateService
  end
  end
  end
end
