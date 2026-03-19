# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module SelectionMouseHandlerSupport
          module PopupInteractions
            private

            def handle_popup_context_click(event)
              return false unless right_click_press?(event)

              selection = @reader_state_reader.selection
              return false unless selection

              rendered = smh_rendered_content_reader&.rendered_lines
              return false if rendered.nil? || rendered.empty?

              click_anchor = @coordinate_service.anchor_from_point({ x: event[:x], y: event[:y] }, rendered,
                                                                   bias: :nearest)
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
              @reader_session_mutator.update_reader(popup_menu: popup_menu)
              return false unless popup_menu&.visible

              switch_mode(:popup_menu)
              draw_screen
              true
            end

            def right_click_press?(event)
              button = event[:button].to_i
              !event[:released] && (button & 0b11) == 2 && button.nobits?(32)
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
                @reader_session_mutator.update_reader(popup_menu: nil)
                @mouse_handler.reset
                @reader_session_mutator.clear_selection
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

            def copy_to_clipboard(text)
              ui = smh_ui_controller
              clip = smh_clipboard_service
              return false unless clip

              clip.copy_with_feedback(text) do |message|
                ui&.set_message(message)
              rescue Shoko::Error
                # best-effort
              end
            rescue Shoko::ClipboardError => e
              ui&.set_message("Copy failed: #{e.message}")
              false
            end

            def dictionary_lookup_available?
              dict_avail = smh_dictionary_availability
              return false unless dict_avail
              return false unless dict_avail.sqlite3_available?

              backend = @config_reader.dictionary_backend
              return false if backend.to_s.downcase == 'disabled'

              true
            rescue Shoko::DependencyUnavailableError
              dictionary_lookup_unavailable
            end

            def dictionary_lookup_unavailable
              false
            end
          end
        end
      end
    end
  end
end
