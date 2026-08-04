# frozen_string_literal: true

require 'shoko/shared/terminal/mouse_button'
require 'shoko/core/models/selection_anchor'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Owns the reader's text-selection and context-menu state machine.
          # Selection text and release suppression live here rather than on the
          # session coordinator, alongside the transitions that mutate them.
          class SelectionInteraction
            StateDependencies = Data.define(
              :reader_state_reader,
              :reader_session_mutator,
              :rendered_content_reader,
              :config_reader
            )
            ServiceDependencies = Data.define(
              :coordinate_service,
              :selection_service,
              :mouse_handler,
              :dictionary_availability,
              :ui_component_factory,
              :popup_position_service,
              :clipboard_service
            )
            Callbacks = Data.define(:ui_controller, :draw, :switch_mode, :popup_action)

            def initialize(state:, services:, callbacks:)
              assign_state_dependencies(state)
              assign_service_dependencies(services)
              assign_callbacks(callbacks)
              @selected_text = nil
              @suppress_popup_release_once = false
            end

            def clear
              @reader_session_mutator.update_reader(popup_menu: nil, hovered_inline_link: nil)
              @mouse_handler&.reset
              @reader_session_mutator.clear_selection
            end

            def handle_overlay?(event)
              return handle_popup_event?(event) if popup_menu_active?
              return true if context_click_handled?(event)
              return false unless event[:released]

              if annotation_editor_visible?
                handle_annotation_editor_click(event)
                return true
              end

              blocked?
            end

            def blocked?
              dictionary_popup_visible? || translator_visible? || in_book_search_popup_visible?
            end

            def finish_selection
              update_selection(@mouse_handler.selection_range)
              selection = @reader_state_reader.selection
              return unless selection

              @selected_text = extract_selected_text(selection)
              return if @selected_text && !@selected_text.strip.empty?

              @mouse_handler.reset
              @reader_session_mutator.clear_selection
            end

            def update_selection(mouse_range)
              anchor_range = anchor_range_from_mouse(mouse_range)
              if anchor_range
                @reader_session_mutator.update_reader(selection: anchor_range)
              else
                @reader_session_mutator.clear_selection
              end
            end

            def dictionary_available?
              availability = @dictionary_availability
              return false unless availability&.sqlite3_available?

              backend = @config_reader.dictionary_backend
              backend.to_s.downcase != 'disabled'
            end

            def context_click_handled?(event)
              return false unless Shoko::Shared::Terminal::MouseButton.right_click_press?(event)

              context = popup_context_click_data(event)
              return false unless context

              popup_menu = open_popup(anchor_position: context[:anchor_position])
              @suppress_popup_release_once = true if popup_menu
              !popup_menu.nil?
            end

            def open_popup(anchor_position: nil)
              popup_menu = build_popup(anchor_position: anchor_position)
              return nil unless popup_menu

              @reader_session_mutator.update_reader(popup_menu: popup_menu, popup_menu_selected: 0)
              return nil unless popup_menu.visible

              @switch_mode.call(:popup_menu)
              @draw.call
              popup_menu
            end

            private

            def assign_state_dependencies(state)
              @reader_state_reader = state.reader_state_reader
              @reader_session_mutator = state.reader_session_mutator
              @rendered_content_reader = state.rendered_content_reader
              @config_reader = state.config_reader
            end

            def assign_service_dependencies(services)
              @coordinate_service = services.coordinate_service
              @selection_service = services.selection_service
              @mouse_handler = services.mouse_handler
              @dictionary_availability = services.dictionary_availability
              @ui_component_factory = services.ui_component_factory
              @popup_position_service = services.popup_position_service
              @clipboard_service = services.clipboard_service
            end

            def assign_callbacks(callbacks)
              @ui_controller = callbacks.ui_controller
              @draw = callbacks.draw
              @switch_mode = callbacks.switch_mode
              @popup_action = callbacks.popup_action
            end

            def handle_popup_event?(event)
              event[:released] ? handle_popup_release(event) : handle_popup_hover(event)
              true
            end

            def handle_popup_release(event)
              if @suppress_popup_release_once
                @suppress_popup_release_once = false
                return
              end

              handle_popup_click(event)
            end

            def handle_annotation_editor_click(event)
              coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])
              controller = @ui_controller.call(:controller)
              result = controller.handle_annotation_editor_overlay_click(coords[:x], coords[:y])
              controller.handle_annotation_editor_overlay_event(result) if result
              @mouse_handler.reset
            ensure
              @draw.call
            end

            def popup_menu_active?
              @reader_state_reader.popup_menu&.visible
            end

            def popup_controller
              @ui_controller.call(:controller)
            end

            def dictionary_popup_visible?
              popup_controller&.dictionary_visible? == true
            end

            def annotation_editor_visible?
              popup_controller&.annotation_editor_visible? == true
            end

            def in_book_search_popup_visible?
              popup_controller&.in_book_search_visible? == true
            end

            def translator_visible?
              popup_controller&.translator_visible? == true
            end

            def build_popup(anchor_position:)
              selection = @reader_state_reader.selection
              return nil unless selection

              rendered = popup_rendered_lines
              return nil unless rendered && @ui_component_factory

              @ui_component_factory.enhanced_popup_menu(
                selection: selection,
                coordinate_service: @coordinate_service,
                reader_state_reader: @reader_state_reader,
                reader_session_mutator: @reader_session_mutator,
                popup_position_service: @popup_position_service,
                clipboard_service: @clipboard_service,
                rendered: rendered,
                dictionary_enabled: dictionary_available?,
                anchor_position: anchor_position
              )
            end

            def popup_context_click_data(event)
              selection = @reader_state_reader.selection
              rendered = popup_rendered_lines
              return nil unless selection && rendered

              click_anchor = @coordinate_service.anchor_from_point(
                { x: event[:x], y: event[:y] }, rendered, bias: :nearest
              )
              return nil unless click_anchor && anchor_within_selection?(click_anchor, selection, rendered)
              return nil unless selected_text(selection)

              { anchor_position: @coordinate_service.mouse_to_terminal(event[:x], event[:y]) }
            end

            def popup_rendered_lines
              rendered = @rendered_content_reader&.rendered_lines
              return nil if rendered.nil? || rendered.empty?

              rendered
            end

            def selected_text(selection)
              text = @selected_text || extract_selected_text(selection)
              return nil if text.nil? || text.strip.empty?

              text
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
              coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])
              item = @reader_state_reader.popup_menu&.handle_click(coords[:x], coords[:y])

              if item
                @popup_action.call(item)
              else
                @reader_session_mutator.update_reader(popup_menu: nil)
                @mouse_handler.reset
                @reader_session_mutator.clear_selection
              end
              @draw.call
            end

            def handle_popup_hover(event)
              coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])
              result = @reader_state_reader.popup_menu&.handle_hover(coords[:x], coords[:y])
              @draw.call if result && result[:type] == :selection_change
            end

            def extract_selected_text(range)
              return nil unless @selection_service && @rendered_content_reader

              @selection_service.extract_text(range, @rendered_content_reader.rendered_lines)
            end

            def anchor_range_from_mouse(mouse_range)
              return nil unless mouse_range

              rendered = @rendered_content_reader&.rendered_lines
              return nil if rendered.nil? || rendered.empty?

              start_anchor = @coordinate_service.anchor_from_point(mouse_range[:start], rendered, bias: :leading)
              end_anchor = @coordinate_service.anchor_from_point(mouse_range[:end], rendered, bias: :trailing)
              return nil unless start_anchor && end_anchor

              @coordinate_service.normalize_selection_range(
                { start: start_anchor.to_h, end: end_anchor.to_h }, rendered
              )
            end
          end
        end
      end
    end
  end
end
