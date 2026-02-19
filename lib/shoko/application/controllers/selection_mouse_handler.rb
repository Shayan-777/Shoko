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
          sel = @reader_state_reader.selection
          return unless sel

          @selected_text = extract_selected_text(sel)

          if @selected_text && !@selected_text.strip.empty?
            show_popup_menu
          else
            @mouse_handler.reset
            @state_writer.clear_selection
          end
        end

        def show_popup_menu
          selection = @reader_state_reader.selection
          return unless selection

          rendered = smh_rendered_content_reader&.rendered_lines
          factory = smh_ui_component_factory
          return unless factory

          popup_menu = factory.enhanced_popup_menu(
            selection: selection,
            coordinate_service: @coordinate_service,
            popup_position_service: @popup_position_service,
            clipboard_service: smh_clipboard_service,
            rendered: rendered,
            dictionary_enabled: dictionary_lookup_available?
          )
          @state_writer.update_reader(popup_menu: popup_menu)
          return unless popup_menu&.visible

          switch_mode(:popup_menu)
          draw_screen
        end

        def handle_popup_click(event)
          terminal_coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])
          popup_menu = @reader_state_reader.popup_menu
          item = popup_menu.handle_click(terminal_coords[:x], terminal_coords[:y])

          if item
            handle_popup_action(item)
          else
            @state_writer.update_reader(popup_menu: nil)
            @mouse_handler.reset
            @state_writer.clear_selection
          end
          draw_screen
        end

        def extract_selected_text(range)
          sel_svc = smh_selection_service
          content_reader = smh_rendered_content_reader
          return nil unless sel_svc && content_reader

          rendered = content_reader.rendered_lines
          sel_svc.extract_text(range, rendered)
        end

        def update_state_selection(mouse_range)
          anchor_range = anchor_range_from_mouse(mouse_range)
          if anchor_range
            @state_writer.update_reader(selection: anchor_range)
          else
            @state_writer.clear_selection
          end
        end

        def anchor_range_from_mouse(mouse_range)
          return nil unless mouse_range

          rendered = smh_rendered_content_reader&.rendered_lines
          return nil if rendered.nil? || rendered.empty?

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

          return false unless dict_avail.sqlite3_available?

          backend = @config_reader.dictionary_backend
          backend_name = backend.to_s.downcase
          return false if backend_name == 'disabled'
          true
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
