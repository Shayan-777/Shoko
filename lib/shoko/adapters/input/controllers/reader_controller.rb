# frozen_string_literal: true

require 'forwardable'
require 'shoko/shared/errors'
require_relative 'reader/intent_runtime_bridge'
require_relative 'reader/runtime_types'
require_relative 'reader/runtime_setup'
require_relative 'reader/state_observer'
require_relative 'reader/progress_autosave'
require_relative 'reader/toc_anchor_resolver'
require_relative 'reader/inline_link_navigator'
require_relative 'reader/render_mailbox'
require_relative 'reader/bar_overlay_mouse_router'
require_relative 'reader/selection_interaction'

require_relative 'reader/input_router'
require_relative 'reader/event_loop'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Coordinator class for the reading experience.
        #
        # Owns reader-session orchestration: runtime setup, lifecycle entry,
        # controller/coordinator delegation, and the top-level input decision
        # order. Distinct mutable/change axes live in collaborators: render
        # signaling, bar-overlay pointer routing, selection/context-menu state,
        # inline-link interaction, and input-sequence filtering.
        class ReaderController
          extend Forwardable

          CONTEXT_DELEGATORS = {
            context: %i[path doc metrics_start_time],
            services: %i[page_calculator terminal_service clipboard_service instrumentation],
            controllers: %i[ui_controller state_controller input_controller],
            coordinators: %i[lifecycle pagination_coordinator render_coordinator],
          }.freeze

          UI_CONTROLLER_METHODS = %i[
            switch_mode
            open_annotations
            show_help
            toggle_view_mode
            increase_line_spacing
            decrease_line_spacing
            toggle_page_numbering_mode
            handle_popup_action
            open_dictionary_lookup
            submit_dictionary_lookup
            close_dictionary_lookup
            dictionary_insert_char
            dictionary_backspace
            dictionary_confirm
            dictionary_tab
            dictionary_swap_languages
            dictionary_scroll_up
            dictionary_scroll_down
            dictionary_toggle_fuzzy
            dictionary_cycle_result
            dictionary_cycle_pair
            open_in_book_search
            close_in_book_search
            submit_in_book_search
            open_search_result
            open_toc_lookup
            close_toc_lookup
            edit_toc_filter
            move_toc_selection
            activate_toc_selection
            open_translator
            close_translator
            edit_translator
            translator_confirm
            translator_cursor_move
            translator_cycle_picker
            translator_open_picker
            translator_paste_source
            translator_copy_translation
            translator_swap_languages
            open_notes_lookup
            close_notes_lookup
            move_notes_selection
            confirm_notes_selection
            edit_selected_note
            new_note
            delete_selected_note
            edit_note_input
            move_note_cursor
            annotation_editor_move_left
            annotation_editor_move_right
            annotation_editor_move_up
            annotation_editor_move_down
            annotation_editor_spellcheck
            annotation_editor_enter
            close_annotation_editor_overlay
          ].freeze

          STATE_CONTROLLER_METHODS = %i[
            save_progress
            load_progress
            load_bookmarks
            add_bookmark
            quit_to_menu
            quit_application
          ].freeze

          INPUT_CONTROLLER_METHODS = %i[
            handle_popup_navigation
            handle_popup_action_key
            handle_popup_cancel
            handle_popup_menu_input
          ].freeze

          RENDER_COORDINATOR_METHODS = %i[
            draw_screen
            refresh_highlighting
            render_loading_overlay
            build_component_layout
            rebuild_root_layout
            apply_theme_palette
          ].freeze

          PAGINATION_COORDINATOR_METHODS = %i[
            pending_initial_calculation?
            perform_initial_calculations_if_needed
            defer_page_map?
            schedule_background_page_map_build
            clear_defer_page_map!
            arm_deferred_page_map!
            rebuild_pagination
            invalidate_pagination_cache
            recalculating?
          ].freeze

          CONTEXT_DELEGATORS.each { |target, methods| def_delegators target, *methods }
          def_delegators :ui_controller, *UI_CONTROLLER_METHODS
          def_delegators :state_controller, *STATE_CONTROLLER_METHODS
          def_delegators :input_controller, *INPUT_CONTROLLER_METHODS
          def_delegators :render_coordinator, *RENDER_COORDINATOR_METHODS
          def_delegators :pagination_coordinator, *PAGINATION_COORDINATOR_METHODS
          def_delegators :lifecycle, :background_worker

          attr_reader :context,
                      :services,
                      :controllers,
                      :coordinators,
                      :observer_registry,
                      :clock,
                      :selection_service,
                      :coordinate_service,
                      :rendered_content_reader,
                      :reader_state_reader,
                      :reader_session_mutator,
                      :config_reader,
                      :references,
                      :navigation_service,
                      :bookmark_service,
                      :annotation_service,
                      :popup_position_service,
                      :logger,
                      :process_control,
                      :intent_handler

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
            [core, state, services, runtime_boot, runtime_startup].each(&:validate!)

            @context = Reader::RuntimeTypes.context_for(epub_path)
            @services = Reader::RuntimeTypes.services_for(core)
            @references = Reader::RuntimeTypes.references_for(core: core, state: state, services: services)
            assign_service_references(@references)
            assign_state_references(@references)
            @render_mailbox = Reader::RenderMailbox.new(wake_input: -> { terminal_service.wake_input })
            @observer_registry = state.observer_registry
            @state_observer = Reader::StateObserver.new(
              controller: self,
              progress_autosave: Reader::ProgressAutosave.new(controller: self, clock: @clock)
            )
            apply_runtime_setup!(
              build_runtime_setup(epub_path, runtime_boot, runtime_startup, runtime_components_factory)
            )
            bootstrap_mouse!(mouse_support, mouse_handler, render_state_writer)
          end

          def apply_runtime_setup!(setup)
            assign_runtime_setup(setup)
            finalize_runtime_setup
            self
          end
          private :apply_runtime_setup!

          def state_changed(path, _old_value, new_value) = @state_observer.handle(path, new_value)

          def activate_input_for_mode(mode) = input_controller&.activate_for_mode(mode)

          def perform_first_paint = @render_metrics.perform_first_paint(draw_screen: -> { draw_screen })

          def dispatch_input_keys(keys) = @input_router.dispatch_input_keys(keys)

          def clear_active_selection = clear_selection!

          def annotation_editor_active? = @input_router.annotation_editor_active?

          # Remove observer registrations created during this reader session.
          def cleanup_observers
            @observer_registry&.remove_observer(self)
            render_coordinator&.cleanup_observers
          rescue Shoko::Error => e
            @logger&.debug('reader_controller.cleanup_observers_failed', error: e.class.name, message: e.message)
          end

          def main_loop
            Reader::EventLoop.new(
              self,
              @reader_state_reader,
              metrics_start_time,
              instrumentation,
              clock: @clock
            ).run
          end

          def mark_metrics_start! = context.metrics_start_time = monotonic_now

          # True once per terminal-resize burst (SIGWINCH); the event loop
          # redraws so the resize applies while the reader is otherwise idle.
          def consume_pending_resize?
            terminal_service.consume_resize_event?
          end

          # Marks a render as pending and wakes the event loop's blocked input
          # read. Safe from worker threads: the flag is only consumed (and the
          # frame drawn) on the UI thread, mirroring the resize path.
          def request_render
            @render_mailbox.request
          end

          # True once per render-request burst; the event loop redraws and the
          # next blocking read resumes.
          def consume_render_request?
            @render_mailbox.consume?
          end

          # Relays carrying async results (e.g. translations) back to the UI
          # thread; registered during composition, drained by the event loop.
          def register_async_relay(relay)
            @render_mailbox.register(relay)
          end

          def drain_async_results
            @render_mailbox.drain
          end

          def async_work_pending?
            @render_mailbox.busy?
          end

          # Mouse reporting is enabled for the whole session and always torn
          # down, then the lifecycle coordinator owns the run loop.
          def run
            terminal_service.enable_mouse
            drain_input_buffer
            lifecycle.run
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
            selection_interaction.clear
          end

          private

          def assign_service_references(references)
            @navigation_service = references.navigation_service
            @bookmark_service = references.bookmark_service
            @popup_position_service = references.popup_position_service
            @logger = references.logger
            @process_control = references.process_control
            @clock = references.clock
            @selection_service = references.selection_service
            @wrapping_service = references.wrapping_service
            @rendered_content_reader = references.rendered_content_reader
            @annotation_service = references.annotation_service
            @coordinate_service = references.coordinate_service
          end

          def assign_state_references(references)
            @reader_state_reader = references.reader_state_reader
            @reader_session_mutator = references.reader_session_mutator
            @ui_state_reader = references.ui_state_reader
            @config_reader = references.config_reader
          end

          def build_runtime_setup(epub_path, runtime_boot, runtime_startup, runtime_components_factory)
            Reader::RuntimeSetup.new(
              controller: self,
              epub_path: epub_path,
              boot: runtime_boot,
              startup: runtime_startup,
              runtime_components_factory: runtime_components_factory
            ).call
          end

          def assign_runtime_setup(setup)
            @context.doc = setup.document
            @startup_loader = setup.startup_loader
            @pending_jump_handler = setup.pending_jump_handler
            @controllers = setup.controllers
            @coordinators = Reader::RuntimeTypes::Coordinators.new(
              lifecycle: setup.lifecycle,
              pagination_coordinator: setup.pagination_coordinator,
              render_coordinator: setup.render_coordinator
            )
            @input_router = setup.input_router
            @render_metrics = setup.render_metrics
            @intent_handler = setup.intent_handler
          end

          def finalize_runtime_setup
            apply_theme_palette
            @startup_loader.apply_pending_jump(jump_handler: @pending_jump_handler)
            build_component_layout
            input_controller.setup_input_dispatcher(@intent_handler)
            @reader_session_mutator.update_reader(running: true)
          end

          def monotonic_now = @clock.monotonic_now

          # Delegate wrapping through the DI-backed wrapping service when available.
          def wrap_lines(lines, width)
            if @wrapping_service
              chapter_index = @reader_state_reader&.current_chapter || 0
              return @wrapping_service.wrap_lines(lines, chapter_index, width)
            end

            lines
          end

          # Clear popup UI state and any local selection handlers.
          def cleanup_popup_state
            ui_controller.cleanup_popup_state
            clear_selection!
          end

          # ===== mouse state machine =====

          def bootstrap_mouse!(mouse_support, mouse_handler, render_state_writer)
            assign_mouse_dependencies(mouse_support, mouse_handler, render_state_writer)
            validate_mouse_dependencies!
            bootstrap_mouse_state
          end

          def assign_mouse_dependencies(mouse_support, mouse_handler, render_state_writer)
            @render_state_writer = render_state_writer
            @mouse_handler = mouse_handler
            @dictionary_availability = mouse_support.dictionary_availability
            @ui_component_factory = mouse_support.ui_component_factory
            @inline_link_navigator = build_inline_link_navigator(mouse_support)
          end

          def validate_mouse_dependencies!
            raise ArgumentError, 'render_state_writer is required' if @render_state_writer.nil?
            raise ArgumentError, 'annotation_service is required' if @annotation_service.nil?
          end

          def bootstrap_mouse_state
            selection_interaction.clear
            @render_state_writer.clear_rendered_lines
            refresh_annotations
          end

          def filter_mouse_sequences(keys)
            input_sequence_filter.filter(keys)
          end

          def handle_mouse_input(input)
            event = @mouse_handler.parse_mouse_event(input)
            return unless event

            return if handle_bar_overlay_mouse(event)
            return if handle_overlay_click(event)

            handle_content_mouse_event(event)
          end

          # The five bar-anchored overlays (in-book search, dictionary, TOC,
          # translator, notes) are driven by the same per-mode ↑/↓/⏎/Esc bindings
          # the keyboard uses, so mouse just maps onto them:
          #
          #   * the wheel scrolls (synthesised arrows);
          #   * moving over a row previews it (a dim hover highlight tracks the
          #     pointer without disturbing the arrow-key selection);
          #   * pressing a row moves the real selection cursor there;
          #   * releasing activates it (⏎ → jump to that entry);
          #   * pressing/releasing in the book above the panel dismisses it (Esc).
          #
          # While an overlay owns the screen it consumes every mouse event so
          # nothing bleeds through to text selection.
          def handle_bar_overlay_mouse(event)
            bar_overlay_mouse_router.handle(event)
          end

          def handle_overlay_click(event)
            selection_interaction.handle_overlay?(event)
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

          def bar_overlay_mouse_router
            @bar_overlay_mouse_router ||= Reader::BarOverlayMouseRouter.new(
              reader_state_reader: @reader_state_reader,
              reader_session_mutator: @reader_session_mutator,
              coordinate_service: @coordinate_service,
              dispatch_keys: ->(keys) { dispatch_input_keys(keys) },
              dispatch_intent: ->(intent, payload) { input_controller&.dispatch_reader_intent(intent, payload) },
              draw: -> { draw_screen }
            )
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
              logger: @logger
            )
          end

          def sync_inline_link_hover(event)
            inline_link_interaction.sync_hover(event)
          end

          def content_mouse_blocked?
            selection_interaction.blocked?
          end

          def handle_content_mouse_result(result)
            case result[:type]
            when :selection_drag
              selection_interaction.update_selection(@mouse_handler.selection_range)
              refresh_highlighting
            when :selection_end
              selection_interaction.finish_selection
              draw_screen
            else
              draw_screen
            end
          end

          def build_anchor_resolver(mouse_support)
            Reader::TocAnchorResolver.new(
              document_reader: -> { doc },
              formatting_service: mouse_support.formatting_service,
              layout_service: mouse_support.layout_service,
              ui_state_reader: mouse_support.ui_state_reader || @ui_state_reader,
              config_reader: @config_reader
            )
          end

          def input_sequence_filter
            @input_sequence_filter ||= InputSequenceFilter.new(
              mouse_handler: @mouse_handler,
              handle_mouse_input: ->(input) { handle_mouse_input(input) }
            )
          end

          def inline_link_interaction
            @inline_link_interaction ||= InlineLinkInteraction.new(
              inline_link_navigator: @inline_link_navigator,
              reader_state_reader: @reader_state_reader,
              reader_session_mutator: @reader_session_mutator
            )
          end

          def popup_ui_controller
            controllers&.ui_controller
          end

          def refresh_annotations
            annotations = @annotation_service.list_for_book(path)
            @reader_session_mutator.update_reader(annotations: annotations)
          end

          # ===== text selection + right-click context menu =====

          def popup_context_click_handled?(event)
            selection_interaction.context_click_handled?(event)
          end

          def open_popup_menu(anchor_position: nil)
            selection_interaction.open_popup(anchor_position: anchor_position)
          end

          def dictionary_lookup_available?
            selection_interaction.dictionary_available?
          end

          def handle_selection_end
            selection_interaction.finish_selection
          end

          def update_state_selection(mouse_range)
            selection_interaction.update_selection(mouse_range)
          end

          def selection_interaction
            @selection_interaction ||= Reader::SelectionInteraction.new(
              state: selection_state_dependencies,
              services: selection_service_dependencies,
              callbacks: selection_callbacks
            )
          end

          def selection_state_dependencies
            Reader::SelectionInteraction::StateDependencies.new(
              reader_state_reader: @reader_state_reader,
              reader_session_mutator: @reader_session_mutator,
              rendered_content_reader: @rendered_content_reader,
              config_reader: @config_reader
            )
          end

          def selection_service_dependencies
            Reader::SelectionInteraction::ServiceDependencies.new(
              coordinate_service: @coordinate_service,
              selection_service: @selection_service,
              mouse_handler: @mouse_handler,
              dictionary_availability: @dictionary_availability,
              ui_component_factory: @ui_component_factory,
              popup_position_service: @popup_position_service,
              clipboard_service: services&.clipboard_service
            )
          end

          def selection_callbacks
            Reader::SelectionInteraction::Callbacks.new(
              ui_controller: ->(_request) { popup_ui_controller },
              draw: -> { draw_screen },
              switch_mode: ->(mode) { switch_mode(mode) },
              popup_action: ->(item) { handle_popup_action(item) }
            )
          end
        end
      end
    end
  end
end

# Required after the class body so the collaborators can reopen ReaderController
# and nest under it (they are part of this reader's mouse state machine).
require_relative 'reader_controller/input_sequence_filter'
require_relative 'reader_controller/inline_link_interaction'
