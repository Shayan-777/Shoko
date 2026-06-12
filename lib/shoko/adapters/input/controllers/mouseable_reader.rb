# frozen_string_literal: true

require_relative 'reader_controller'
require_relative 'sidebar_mouse_handler'
require_relative 'selection_mouse_handler'
require_relative 'sidebar/anchor_resolver'
require_relative 'reader/inline_link_navigator'
require_relative 'mouseable_reader/input_sequence_filter'
require_relative 'mouseable_reader/inline_link_interaction'

module Shoko
  module Adapters
    module Input
      module Controllers
        # A Reader that supports mouse interactions for annotations.
        class MouseableReader < ReaderController
          include SelectionMouseHandler

          def initialize(
            epub_path,
            core:,
            state:,
            services:,
            runtime_boot:,
            runtime_startup:,
            mouse_support:,
            mouse_handler:,
            runtime_components_factory:, render_state_writer: nil
          )
            super(
              epub_path,
              core: core,
              state: state,
              services: services,
              runtime_boot: runtime_boot,
              runtime_startup: runtime_startup,
              runtime_components_factory: runtime_components_factory
            )

            assign_mouse_dependencies(mouse_support, mouse_handler, render_state_writer)
            validate_mouse_dependencies!
            initialize_mouse_helpers
            bootstrap_mouse_state
          end

          def run
            terminal_service.enable_mouse
            drain_input_buffer
            super
          ensure
            terminal_service.disable_mouse
          end

          def drain_input_buffer
            drained = 0
            while terminal_service.read_key
              drained += 1
              break if drained > 20
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

          def clear_selection!
            @reader_session_mutator.update_reader(popup_menu: nil, hovered_inline_link: nil)
            @mouse_handler&.reset
            @reader_session_mutator.clear_selection
          end

          private

          def filter_mouse_sequences(keys)
            input_sequence_filter.filter(keys)
          end

          def spurious_post_mouse_key?(token, ctx)
            return (ctx[:saw_mouse] || ctx[:saw_prefix]) && token == "\e" unless @input_sequence_filter

            @input_sequence_filter.spurious_post_mouse_key?(token, ctx)
          end

          def sidebar_mouse_handler
            @sidebar_mouse_handler ||= SidebarMouseHandler.new(
              mouse_handler: @mouse_handler,
              coordinate_service: @coordinate_service,
              terminal_service: terminal_service,
              render_coordinator: render_coordinator,
              ui_controller: ui_controller,
              clock: @clock_ref,
              redraw: method(:draw_screen)
            )
          end

          def handle_mouse_input(input)
            event = @mouse_handler.parse_mouse_event(input)
            return unless event

            return if handle_overlay_click(event)
            return if sidebar_mouse_handler.handle_sidebar_mouse(event)

            handle_content_mouse_event(event)
          end

          def handle_overlay_click(event)
            return true if popup_overlay_handled?(event)
            return true if popup_context_click_handled?(event)
            return false unless event[:released]

            if annotation_editor_visible?
              handle_annotation_editor_click(event)
              return true
            end

            return true if content_mouse_blocked?

            false
          end

          def consume_suppressed_popup_release?
            return false unless @suppress_popup_release_once

            @suppress_popup_release_once = false
            true
          end

          def handle_content_mouse_event(event)
            return if content_mouse_blocked?

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

            handle_content_mouse_result(result)
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

          def consume_inline_link_click(event)
            inline_link_interaction.consume_click(event, mouse_handler: @mouse_handler)
          end

          def build_inline_link_navigator(mouse_support)
            Reader::InlineLinkNavigator.new(
              coordinate_service: @coordinate_service,
              rendered_content_reader: @rendered_content_reader,
              reader_state_reader: @reader_state_reader,
              document_reader: -> { doc },
              state_controller: state_controller,
              anchor_resolver: build_anchor_resolver(mouse_support),
              logger: @logger_ref
            )
          end

          def sync_inline_link_hover(event)
            inline_link_interaction.sync_hover(event)
          end

          def popup_overlay_handled?(event)
            return false unless popup_menu_active?

            event[:released] ? handle_popup_release(event) : handle_popup_hover(event)
            true
          end

          def handle_popup_release(event)
            return if consume_suppressed_popup_release?

            handle_popup_click(event)
          end

          def content_mouse_blocked?
            dictionary_popup_visible? || translator_visible? || in_book_search_popup_visible?
          end

          def handle_content_mouse_result(result)
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

          def build_anchor_resolver(mouse_support)
            Sidebar::AnchorResolver.new(
              document_reader: -> { doc },
              formatting_service: mouse_support.formatting_service,
              layout_service: mouse_support.layout_service,
              ui_state_reader: mouse_support.ui_state_reader || @ui_state_reader,
              config_reader: @config_reader,
              sidebar_state_reader: @reader_state_reader
            )
          end

          def input_sequence_filter
            @input_sequence_filter ||= MouseableReaderSupport::InputSequenceFilter.new(
              mouse_handler: @mouse_handler,
              handle_mouse_input: ->(input) { handle_mouse_input(input) }
            )
          end

          def inline_link_interaction
            @inline_link_interaction ||= MouseableReaderSupport::InlineLinkInteraction.new(
              inline_link_navigator: @inline_link_navigator,
              reader_state_reader: @reader_state_reader,
              reader_session_mutator: @reader_session_mutator
            )
          end

          def assign_mouse_dependencies(mouse_support, mouse_handler, render_state_writer)
            @coordinate_service = @coordinate_service_ref
            @popup_position_service = @popup_position_service_ref
            @render_state_writer = render_state_writer
            @mouse_handler = mouse_handler
            @selection_service = @selection_service_ref
            @rendered_content_reader = rendered_content_reader
            @render_registry = @render_registry_ref
            @clipboard_service = clipboard_service
            @dictionary_availability = mouse_support.dictionary_availability
            @ui_component_factory = mouse_support.ui_component_factory
            @reader_session_mutator = reader_session_mutator
            @inline_link_navigator = build_inline_link_navigator(mouse_support)
          end

          def validate_mouse_dependencies!
            raise ArgumentError, 'render_state_writer is required' if @render_state_writer.nil?
            raise ArgumentError, 'annotation_service is required' if @annotation_service_ref.nil?
          end

          def initialize_mouse_helpers
            @sidebar_scroll_drag_active = false
            @input_sequence_filter = MouseableReaderSupport::InputSequenceFilter.new(
              mouse_handler: @mouse_handler,
              handle_mouse_input: ->(input) { handle_mouse_input(input) }
            )
            @inline_link_interaction = MouseableReaderSupport::InlineLinkInteraction.new(
              inline_link_navigator: @inline_link_navigator,
              reader_state_reader: @reader_state_reader,
              reader_session_mutator: @reader_session_mutator
            )
          end

          def bootstrap_mouse_state
            @reader_session_mutator.update_reader(popup_menu: nil, hovered_inline_link: nil)
            @selected_text = nil
            @reader_session_mutator.clear_selection
            clear_rendered_lines_on_init
            refresh_annotations
          end

          def dictionary_popup_visible?
            popup_ui_controller&.dictionary_visible? == true
          end

          def annotation_editor_visible?
            popup_ui_controller&.annotation_editor_visible? == true
          end

          def in_book_search_popup_visible?
            popup_ui_controller&.in_book_search_visible? == true
          end

          def translator_visible?
            controller = popup_ui_controller
            return false unless controller
            return false unless controller.respond_to?(:translator_visible?)

            controller.translator_visible?
          end

          def popup_menu_active?
            @reader_state_reader.popup_menu&.visible
          end

          def popup_ui_controller
            controllers&.ui_controller
          end

          def refresh_annotations
            annotations = @annotation_service_ref.list_for_book(path)
            @reader_session_mutator.update_reader(annotations: annotations)
          end

          def clear_rendered_lines_on_init
            @render_state_writer.clear_rendered_lines
          end
        end
      end
    end
  end
end
