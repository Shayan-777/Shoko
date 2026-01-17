# frozen_string_literal: true

module Shoko
  module Application
    module Controllers
      # Handles text selection and popup menu mouse interactions.
      # Extracted from MouseableReader to reduce class size.
      module SelectionMouseHandler
        private

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

          rendered = Shoko::Application::Selectors::ReaderSelectors.rendered_lines(state)
          popup_menu = Shoko::Adapters::Output::Ui::Components::EnhancedPopupMenu.new(
            selection, nil, @coordinate_service, clipboard_service, rendered
          )
          state.dispatch(Application::Actions::UpdateReaderAction.new(popup_menu: popup_menu))
          return unless popup_menu&.visible

          switch_mode(:popup_menu)
          draw_screen
        end

        def handle_popup_click(event)
          terminal_coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])
          popup_menu = Shoko::Application::Selectors::ReaderSelectors.popup_menu(state)
          item = popup_menu.handle_click(terminal_coords[:x], terminal_coords[:y])

          if item
            handle_popup_action(item)
          else
            state.dispatch(Application::Actions::UpdateReaderAction.new(popup_menu: nil))
            @mouse_handler.reset
            state.dispatch(Application::Actions::ClearSelectionAction.new)
          end
          draw_screen
        end

        def extract_selected_text(range)
          selection_service = dependencies.resolve(:selection_service)
          rendered_content_reader = dependencies.resolve(:rendered_content_reader)
          if selection_service.respond_to?(:extract_from_state)
            selection_service.extract_from_state(state, rendered_content_reader: rendered_content_reader, selection_range: range)
          else
            rendered = rendered_content_reader.rendered_lines
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
            nil
          end
          false
        end
      end
    end
  end
end
