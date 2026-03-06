# frozen_string_literal: true

require_relative 'reader_controller'
require_relative 'sidebar_mouse_handler'
require_relative 'selection_mouse_handler'
require_relative 'sidebar/anchor_resolver'
require_relative 'reader/inline_link_navigator'

module Shoko
  module Adapters
    module Input
      module Controllers
        # A Reader that supports mouse interactions for annotations.
        class MouseableReader < ReaderController
          include SidebarMouseHandler
          include SelectionMouseHandler

          def initialize(epub_path, deps:, mouse_handler:, render_state_writer: nil, runtime_components_factory:)
            super(
              epub_path,
              deps: deps,
              runtime_components_factory: runtime_components_factory
            )

            @coordinate_service = @coordinate_service_ref
            @popup_position_service = @popup_position_service_ref
            @render_state_writer = render_state_writer
            @mouse_handler = mouse_handler
            @selection_service = @selection_service_ref
            @rendered_content_reader = deps.rendered_content_reader
            @render_registry = @render_registry_ref
            @clipboard_service = deps.clipboard_service
            @dictionary_availability = deps.dictionary_availability
            @ui_component_factory = deps.ui_component_factory
            @inline_link_navigator = build_inline_link_navigator(deps)
            raise ArgumentError, 'render_state_writer is required' if @render_state_writer.nil?
            raise ArgumentError, 'annotation_service is required' if @annotation_service_ref.nil?

            @mouse_input_buffer = nil
            @sidebar_scroll_drag_active = false
            @state_writer.update_reader(popup_menu: nil, hovered_inline_link: nil)
            @selected_text = nil
            @state_writer.clear_selection
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
            while terminal_service.read_key
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
            @state_writer.update_reader(popup_menu: nil, hovered_inline_link: nil)
            @mouse_handler&.reset
            @state_writer.clear_selection
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
              # Discard stale prefix noise and reprocess the latest token normally
              # so user commands like 'q' are never trapped in an invalid buffer.
              @mouse_input_buffer = nil
              process_unbuffered_token(token, ctx)
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
            # Keep explicit quit behavior deterministic: never drop 'q' here.
            # Only ignore a stray Escape that can be emitted alongside mouse prefixes.
            (ctx[:saw_mouse] || ctx[:saw_prefix]) && token == "\e"
          end

          def handle_mouse_input(input)
            event = @mouse_handler.parse_mouse_event(input)
            return unless event

            return if handle_overlay_click(event)
            return if handle_sidebar_mouse(event)

            handle_content_mouse_event(event)
          end

          def handle_overlay_click(event)
            if popup_menu_active?
              if event[:released]
                if consume_suppressed_popup_release?
                  # Consume the release event that follows context-click open.
                else
                  handle_popup_click(event)
                end
              else
                handle_popup_hover(event)
              end
              return true
            end

            return true if handle_popup_context_click(event)
            return false unless event[:released]

            if annotation_editor_visible?
              handle_annotation_editor_click(event)
              return true
            end

            # Block all mouse events when dictionary popup is open
            return true if dictionary_popup_visible? || in_book_search_popup_visible?

            false
          end

          def consume_suppressed_popup_release?
            return false unless @suppress_popup_release_once

            @suppress_popup_release_once = false
            true
          end

          def dictionary_popup_visible?
            controller = ui_controller
            controller.dictionary_visible?
          end

          def annotation_editor_visible?
            controller = ui_controller
            controller.annotation_editor_visible?
          end

          def in_book_search_popup_visible?
            controller = ui_controller
            controller.in_book_search_visible?
          end

          def popup_menu_active?
            popup = @reader_state_reader.popup_menu
            popup&.visible
          end

          def handle_content_mouse_event(event)
            # Block all content mouse events when dictionary popup is open
            return if dictionary_popup_visible? || in_book_search_popup_visible?
            hover_changed = sync_inline_link_hover(event)
            if consume_inline_link_click(event)
              draw_screen
              return
            end

            result = @mouse_handler.handle_event(event)
            unless result
              draw_screen if hover_changed
              return
            end

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
            controller = ui_controller
            result = controller.handle_annotation_editor_overlay_click(coords[:x], coords[:y])
            controller.handle_annotation_editor_overlay_event(result) if result
            @mouse_handler.reset
          ensure
            draw_screen
          end

          def refresh_annotations
            annotations = @annotation_service_ref.list_for_book(path)
            @state_writer.update_reader(annotations: annotations)
          end

          def clear_rendered_lines_on_init
            @render_state_writer.clear_rendered_lines
          end

          def consume_inline_link_click(event)
            return false unless @inline_link_navigator
            return false unless inline_link_click_candidate?(event)

            navigated = @inline_link_navigator.navigate(event)
            return false unless navigated

            @state_writer.update_reader(popup_menu: nil, hovered_inline_link: nil)
            @state_writer.clear_selection
            @mouse_handler.reset
            true
          end

          def inline_link_click_candidate?(event)
            return false unless @mouse_handler&.selecting

            button = event[:button].to_i
            return false unless event[:released] && button.nobits?(0b11) && button.nobits?(32)

            start_pos = @mouse_handler.selection_start
            end_pos = @mouse_handler.selection_end
            return false unless start_pos && end_pos

            start_pos[:x].to_i == end_pos[:x].to_i &&
              start_pos[:y].to_i == end_pos[:y].to_i
          end

          def build_inline_link_navigator(deps)
            ui_state_reader = if deps.respond_to?(:ui_state_reader)
                                deps.ui_state_reader || @ui_state_reader
                              else
                                @ui_state_reader
                              end

            anchor_resolver = Sidebar::AnchorResolver.new(
              document_reader: -> { doc },
              formatting_service: deps.formatting_service,
              layout_service: deps.layout_service,
              ui_state_reader: ui_state_reader,
              config_reader: @config_reader,
              sidebar_state_reader: @reader_state_reader
            )

            Reader::InlineLinkNavigator.new(
              coordinate_service: @coordinate_service,
              rendered_content_reader: @rendered_content_reader,
              reader_state_reader: @reader_state_reader,
              document_reader: -> { doc },
              state_controller: state_controller,
              anchor_resolver: anchor_resolver,
              logger: @logger_ref
            )
          end

          def sync_inline_link_hover(event)
            return false unless @inline_link_navigator

            hit = @inline_link_navigator.link_hit_for_event(event)
            next_hover = hovered_inline_link_payload(hit)
            current_hover = normalize_hovered_inline_link(@reader_state_reader&.hovered_inline_link)
            return false if current_hover == next_hover

            @state_writer.update_reader(hovered_inline_link: next_hover)
            true
          end

          def hovered_inline_link_payload(hit)
            return nil unless hit.is_a?(Hash)

            start_char = hit[:start_char].to_i
            end_char = hit[:end_char].to_i
            return nil if end_char <= start_char

            href = hit[:href].to_s.strip
            return nil if href.empty?

            {
              chapter_index: @reader_state_reader.current_chapter.to_i,
              line_offset: hit[:line_offset].to_i,
              start_char: start_char,
              end_char: end_char,
              href: href,
            }
          end

          def normalize_hovered_inline_link(value)
            return nil unless value.is_a?(Hash)

            start_char = (value[:start_char] || value['start_char']).to_i
            end_char = (value[:end_char] || value['end_char']).to_i
            href = (value[:href] || value['href']).to_s.strip
            return nil if end_char <= start_char || href.empty?

            {
              chapter_index: (value[:chapter_index] || value['chapter_index']).to_i,
              line_offset: (value[:line_offset] || value['line_offset']).to_i,
              start_char: start_char,
              end_char: end_char,
              href: href,
            }
          end
        end
      end
    end
  end
end
