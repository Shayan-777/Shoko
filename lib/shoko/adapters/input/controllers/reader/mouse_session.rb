# frozen_string_literal: true

require_relative 'bar_overlay_mouse_router'
require_relative 'inline_link_interaction'
require_relative 'inline_link_navigator'
require_relative 'input_sequence_filter'
require_relative 'selection_interaction'
require_relative 'toc_anchor_resolver'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Owns the mutable pointer-input session for a reader. The top-level
          # controller supplies orchestration callbacks; this object owns sequence
          # buffering, hover state, selection state, and pointer routing.
          class MouseSession
            def initialize(controller:, mouse_handler:, mouse_support: nil, render_state_writer: nil,
                           inline_link_navigator: nil, selection_interaction: nil)
              @controller = controller
              @mouse_handler = mouse_handler
              @mouse_support = mouse_support
              @render_state_writer = render_state_writer
              @inline_link_navigator = inline_link_navigator
              @selection_interaction = selection_interaction
            end

            def bootstrap!
              raise ArgumentError, 'render_state_writer is required' unless @render_state_writer
              raise ArgumentError, 'annotation_service is required' unless @controller.annotation_service

              @inline_link_navigator ||= build_inline_link_navigator(@mouse_support)
              selection_interaction.clear
              @render_state_writer.clear_rendered_lines
              refresh_annotations
              self
            end

            def filter(keys)
              input_sequence_filter.filter(keys)
            end

            def handle(input)
              event = @mouse_handler.parse_mouse_event(input)
              return unless event
              return if bar_overlay_mouse_router.handle(event)
              return if selection_interaction.handle_overlay?(event)

              handle_content_event(event)
            end

            def handle_content_event(event)
              return if selection_interaction.blocked?

              hover_changed = inline_link_interaction.sync_hover(event)
              if inline_link_interaction.consume_click(event, mouse_handler: @mouse_handler)
                @controller.draw_screen
                return
              end

              result = @mouse_handler.handle_event(event)
              unless result
                @controller.draw_screen if hover_changed
                return
              end

              handle_content_result(result)
            end

            def clear_selection = selection_interaction.clear
            def handle_overlay?(event) = selection_interaction.handle_overlay?(event)
            def handle_bar_overlay(event) = bar_overlay_mouse_router.handle(event)
            def sync_inline_link_hover(event) = inline_link_interaction.sync_hover(event)
            def context_click_handled?(event) = selection_interaction.context_click_handled?(event)
            def open_popup(anchor_position: nil) = selection_interaction.open_popup(anchor_position: anchor_position)
            def dictionary_available? = selection_interaction.dictionary_available?
            def finish_selection = selection_interaction.finish_selection
            def update_selection(mouse_range) = selection_interaction.update_selection(mouse_range)

            def build_inline_link_navigator(mouse_support)
              return @inline_link_navigator if @inline_link_navigator
              raise ArgumentError, 'mouse_support is required' unless mouse_support

              InlineLinkNavigator.new(
                coordinate_service: @controller.coordinate_service,
                rendered_content_reader: @controller.rendered_content_reader,
                reader_state_reader: @controller.reader_state_reader,
                document_reader: -> { @controller.doc },
                state_controller: @controller.state_controller,
                anchor_resolver: build_anchor_resolver(mouse_support),
                logger: @controller.logger
              )
            end

            private

            def handle_content_result(result)
              case result[:type]
              when :selection_drag
                selection_interaction.update_selection(@mouse_handler.selection_range)
                @controller.refresh_highlighting
              when :selection_end
                selection_interaction.finish_selection
                @controller.draw_screen
              else
                @controller.draw_screen
              end
            end

            def bar_overlay_mouse_router
              @bar_overlay_mouse_router ||= BarOverlayMouseRouter.new(
                reader_state_reader: @controller.reader_state_reader,
                reader_session_mutator: @controller.reader_session_mutator,
                coordinate_service: @controller.coordinate_service,
                dispatch_keys: ->(keys) { @controller.dispatch_input_keys(keys) },
                dispatch_intent: lambda { |intent, payload|
                  @controller.input_controller&.dispatch_reader_intent(intent, payload)
                },
                draw: -> { @controller.draw_screen }
              )
            end

            def input_sequence_filter
              @input_sequence_filter ||= InputSequenceFilter.new(
                mouse_handler: @mouse_handler,
                handle_mouse_input: ->(input) { handle(input) }
              )
            end

            def inline_link_interaction
              @inline_link_interaction ||= InlineLinkInteraction.new(
                inline_link_navigator: @inline_link_navigator,
                reader_state_reader: @controller.reader_state_reader,
                reader_session_mutator: @controller.reader_session_mutator
              )
            end

            def selection_interaction
              @selection_interaction ||= SelectionInteraction.new(
                state: selection_state,
                services: selection_services,
                callbacks: selection_callbacks
              )
            end

            def selection_state
              SelectionInteraction::StateDependencies.new(
                reader_state_reader: @controller.reader_state_reader,
                reader_session_mutator: @controller.reader_session_mutator,
                rendered_content_reader: @controller.rendered_content_reader,
                config_reader: @controller.config_reader
              )
            end

            def selection_services
              SelectionInteraction::ServiceDependencies.new(
                coordinate_service: @controller.coordinate_service,
                selection_service: @controller.selection_service,
                mouse_handler: @mouse_handler,
                dictionary_availability: dictionary_availability,
                ui_component_factory: ui_component_factory,
                popup_position_service: @controller.popup_position_service,
                clipboard_service: @controller.services&.clipboard_service
              )
            end

            def selection_callbacks
              SelectionInteraction::Callbacks.new(
                ui_controller: ->(_request) { @controller.controllers&.ui_controller },
                draw: -> { @controller.draw_screen },
                switch_mode: ->(mode) { @controller.switch_mode(mode) },
                popup_action: ->(item) { @controller.handle_popup_action(item) }
              )
            end

            def build_anchor_resolver(mouse_support)
              TocAnchorResolver.new(
                document_reader: -> { @controller.doc },
                formatting_service: mouse_support.formatting_service,
                layout_service: mouse_support.layout_service,
                ui_state_reader: mouse_support.ui_state_reader || @controller.ui_state_reader,
                config_reader: @controller.config_reader
              )
            end

            def dictionary_availability
              @mouse_support&.dictionary_availability || @controller.instance_variable_get(:@dictionary_availability)
            end

            def ui_component_factory
              @mouse_support&.ui_component_factory || @controller.instance_variable_get(:@ui_component_factory)
            end

            def refresh_annotations
              annotations = @controller.annotation_service.list_for_book(@controller.path)
              @controller.reader_session_mutator.update_reader(annotations: annotations)
            end
          end
        end
      end
    end
  end
end
