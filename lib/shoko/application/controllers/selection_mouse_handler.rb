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

          rendered = Shoko::Application::Selectors::ReaderSelectors.rendered_lines(state,
                                                                                   render_registry: smh_render_registry)
          factory = smh_ui_component_factory
          return unless factory

          popup_menu = factory.enhanced_popup_menu(
            selection: selection,
            coordinate_service: @coordinate_service,
            clipboard_service: smh_clipboard_service,
            rendered: rendered,
            dictionary_enabled: dictionary_lookup_available?
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
          sel_svc = smh_selection_service
          content_reader = smh_rendered_content_reader
          return nil unless sel_svc && content_reader

          if sel_svc.respond_to?(:extract_from_state)
            sel_svc.extract_from_state(state, rendered_content_reader: content_reader,
                                              selection_range: range)
          else
            rendered = content_reader.rendered_lines
            sel_svc.extract_text(range, rendered)
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

          rendered = Shoko::Application::Selectors::ReaderSelectors.rendered_lines(state,
                                                                                   render_registry: smh_render_registry)
          return nil if rendered.empty?

          start_anchor = @coordinate_service.anchor_from_point(mouse_range[:start], rendered, bias: :leading)
          end_anchor = @coordinate_service.anchor_from_point(mouse_range[:end], rendered, bias: :trailing)
          return nil unless start_anchor && end_anchor

          @coordinate_service.normalize_selection_range(
            { start: start_anchor.to_h, end: end_anchor.to_h }, rendered
          )
        end

        def copy_to_clipboard(text)
          ui = smh_ui_controller
          clip = smh_clipboard_service
          return false unless clip

          clip.copy_with_feedback(text) do |message|
            ui&.set_message(message)
          rescue StandardError
            # best-effort
          end
        rescue Shoko::ClipboardError => e
          begin
            ui&.set_message("Copy failed: #{e.message}")
          rescue StandardError
            nil
          end
          false
        end

        def dictionary_lookup_available?
          dict_avail = smh_dictionary_availability
          return false unless dict_avail

          backend = state.get(%i[config dictionary_backend])
          backend_name = backend.to_s.downcase
          env_enabled = dict_avail.env_override_enabled?
          return dict_avail.sqlite3_available? if env_enabled
          return false if backend_name == 'disabled'
          return dict_avail.sqlite3_available? if backend_name == 'sqlite'
          return false unless dict_avail.sqlite3_available?

          dict_path = state.get(%i[config dictionary_path])
          dict_avail.databases_present?(dict_path)
        rescue StandardError
          false
        end

        # Host class provides these dependencies as instance variables.
        # Each method returns the corresponding dependency or nil.
        def smh_selection_service
          defined?(@selection_service) ? @selection_service : nil
        end

        def smh_rendered_content_reader
          defined?(@rendered_content_reader) ? @rendered_content_reader : nil
        end

        def smh_render_registry
          defined?(@render_registry) ? @render_registry : nil
        end

        def smh_ui_controller
          defined?(@ui_controller_ref) ? @ui_controller_ref : nil
        end

        def smh_clipboard_service
          defined?(@clipboard_service) ? @clipboard_service : nil
        end

        def smh_dictionary_availability
          defined?(@dictionary_availability) ? @dictionary_availability : nil
        end

        def smh_ui_component_factory
          defined?(@ui_component_factory) ? @ui_component_factory : nil
        end
      end
    end
  end
end
