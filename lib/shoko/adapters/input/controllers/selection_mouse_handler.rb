# frozen_string_literal: true

require_relative '../../../core/models/selection_anchor'

module Shoko
  module Adapters
    module Input
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

            unless @selected_text && !@selected_text.strip.empty?
              @mouse_handler.reset
              @state_writer.clear_selection
            end
          end

          def handle_popup_context_click(event)
            return false unless right_click_press?(event)

            selection = @reader_state_reader.selection
            return false unless selection

            rendered = smh_rendered_content_reader&.rendered_lines
            return false if rendered.nil? || rendered.empty?

            click_anchor = @coordinate_service.anchor_from_point({ x: event[:x], y: event[:y] }, rendered, bias: :nearest)
            return false unless click_anchor && anchor_within_selection?(click_anchor, selection, rendered)

            selected_text = @selected_text || extract_selected_text(selection)
            return false if selected_text.nil? || selected_text.strip.empty?

            terminal_coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])
            opened = show_popup_menu(anchor_position: terminal_coords)
            @suppress_popup_release_once = true if opened
            opened
          end

          def show_popup_menu(anchor_position: nil)
            selection = @reader_state_reader.selection
            return false unless selection

            rendered = smh_rendered_content_reader&.rendered_lines
            factory = smh_ui_component_factory
            return false unless factory

            popup_menu = factory.enhanced_popup_menu(
              selection: selection,
              coordinate_service: @coordinate_service,
              popup_position_service: @popup_position_service,
              clipboard_service: smh_clipboard_service,
              rendered: rendered,
              dictionary_enabled: dictionary_lookup_available?,
              anchor_position: anchor_position
            )
            @state_writer.update_reader(popup_menu: popup_menu)
            return false unless popup_menu&.visible

            switch_mode(:popup_menu)
            draw_screen
            true
          end

          def right_click_press?(event)
            button = event[:button].to_i
            !event[:released] && (button & 0b11) == 2 && (button & 32).zero?
          end

          def anchor_within_selection?(anchor, selection, rendered)
            normalized = @coordinate_service.normalize_selection_range(selection, rendered)
            return false unless normalized

            start_anchor = Shoko::Core::Models::SelectionAnchor.from(normalized[:start])
            end_anchor = Shoko::Core::Models::SelectionAnchor.from(normalized[:end])
            return false unless start_anchor && end_anchor

            (start_anchor <=> anchor).to_i <= 0 && (anchor <=> end_anchor).to_i <= 0
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

          def handle_popup_hover(event)
            terminal_coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])
            popup_menu = @reader_state_reader.popup_menu
            return unless popup_menu

            result = popup_menu.handle_hover(terminal_coords[:x], terminal_coords[:y])
            draw_screen if result && result[:type] == :selection_change
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
end
