# frozen_string_literal: true

require 'ostruct'

require_relative 'reader_controller'
require_relative 'sidebar_mouse_handler'
require_relative 'selection_mouse_handler'
require_relative '../../adapters/input/annotations/mouse_handler'
require_relative '../../adapters/output/ui/components/enhanced_popup_menu'
require_relative '../../adapters/output/ui/components/tooltip_overlay_component'

module Shoko
  module Application
    module Controllers
      # A Reader that supports mouse interactions for annotations.
      class MouseableReader < ReaderController
        include SidebarMouseHandler
        include SelectionMouseHandler

        def initialize(epub_path, config = nil, dependencies = nil)
          super

          @coordinate_service = dependencies.resolve(:coordinate_service)
          @render_state_writer = resolve_render_state_writer(dependencies)
          @mouse_handler = Shoko::Adapters::Input::Annotations::MouseHandler.new
          @mouse_input_buffer = nil
          @sidebar_scroll_drag_active = false
          state.dispatch(Application::Actions::UpdateReaderAction.new(popup_menu: nil))
          @selected_text = nil
          state.dispatch(Application::Actions::ClearSelectionAction.new)
          clear_rendered_lines_on_init
          refresh_annotations
        end

        def run
          terminal_service.enable_mouse
          # Clear any stale input from the terminal buffer to prevent
          # spurious keys (like 'q') from immediately triggering actions
          drain_input_buffer
          super
        ensure
          terminal_service.disable_mouse
        end

        # Drain any pending input from the terminal buffer
        # This prevents stale keypresses from being processed as commands
        def drain_input_buffer
          drained = 0
          while (key = terminal_service.read_key)
            drained += 1
            break if drained > 20 # Safety limit
          end
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

        # Clear any active text selection and hide popup
        def clear_selection!
          state.dispatch(Application::Actions::UpdateReaderAction.new(popup_menu: nil))
          @mouse_handler&.reset
          state&.dispatch(Application::Actions::ClearSelectionAction.new)
        end

        private

        def filter_mouse_sequences(keys)
          ctx = { remaining: [], saw_mouse: false, saw_prefix: false }
          keys.each { |token| process_mouse_token(token, ctx) }
          ctx[:remaining]
        end

        def process_mouse_token(token, ctx)
          if @mouse_input_buffer
            process_buffered_token(token, ctx)
          else
            process_unbuffered_token(token, ctx)
          end
        end

        def process_buffered_token(token, ctx)
          @mouse_input_buffer << token

          if @mouse_handler.mouse_sequence?(@mouse_input_buffer)
            handle_mouse_input(@mouse_input_buffer)
            @mouse_input_buffer = nil
            ctx[:saw_mouse] = true
          elsif @mouse_handler.mouse_prefix?(@mouse_input_buffer)
            ctx[:saw_prefix] = true
          else
            ctx[:remaining] << @mouse_input_buffer
            @mouse_input_buffer = nil
          end
        end

        def process_unbuffered_token(token, ctx)
          if @mouse_handler.mouse_sequence?(token)
            handle_mouse_input(token)
            ctx[:saw_mouse] = true
          elsif @mouse_handler.mouse_prefix?(token)
            @mouse_input_buffer = String(token)
            ctx[:saw_prefix] = true
          elsif spurious_post_mouse_key?(token, ctx)
            # Skip spurious keys after mouse events
          else
            ctx[:remaining] << token
          end
        end

        def spurious_post_mouse_key?(token, ctx)
          (ctx[:saw_mouse] || ctx[:saw_prefix]) && %w[q \e].include?(token)
        end

        def handle_mouse_input(input)
          event = @mouse_handler.parse_mouse_event(input)
          return unless event

          return if handle_overlay_click(event)
          return if handle_sidebar_mouse(event)

          handle_content_mouse_event(event)
        end

        def handle_overlay_click(event)
          return false unless event[:released]

          if annotation_editor_visible?
            handle_annotation_editor_click(event)
            return true
          end

          if popup_menu_active?
            handle_popup_click(event)
            return true
          end

          # Block all mouse events when dictionary popup is open
          if dictionary_popup_visible?
            return true
          end

          false
        end

        def dictionary_popup_visible?
          popup = Shoko::Application::Selectors::ReaderSelectors.dictionary_popup(state)
          popup.respond_to?(:visible?) && popup.visible?
        end

        def annotation_editor_visible?
          overlay = Shoko::Application::Selectors::ReaderSelectors.annotation_editor_overlay(state)
          overlay.respond_to?(:visible?) && overlay.visible?
        end

        def popup_menu_active?
          popup = Shoko::Application::Selectors::ReaderSelectors.popup_menu(state)
          popup&.visible
        end

        def handle_content_mouse_event(event)
          # Block all content mouse events when dictionary popup is open
          return if dictionary_popup_visible?

          result = @mouse_handler.handle_event(event)
          return unless result

          case result[:type]
          when :selection_drag
            update_state_selection(@mouse_handler.selection_range)
            refresh_highlighting
          when :selection_end
            handle_selection_end
            draw_screen
          else
            draw_screen
          end
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

        def refresh_annotations
          service = dependencies.resolve(:annotation_service)
          annotations = service.list_for_book(path)
        rescue StandardError
          annotations = []
        ensure
          state.dispatch(Application::Actions::UpdateReaderAction.new(annotations: annotations || []))
        end

        def clear_rendered_lines_on_init
          @render_state_writer&.clear_rendered_lines
        rescue StandardError
          # Fallback to direct dispatch if port unavailable
          state.dispatch(Application::Actions::ClearRenderedLinesAction.new)
        end

        def resolve_render_state_writer(deps)
          deps.resolve(:render_state_writer)
        rescue StandardError
          nil
        end
      end
    end
  end
end
