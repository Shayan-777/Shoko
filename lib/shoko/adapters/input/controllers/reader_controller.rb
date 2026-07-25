# frozen_string_literal: true

require 'forwardable'
require 'shoko/shared/errors'
require 'shoko/shared/terminal/mouse_button'
require 'shoko/core/models/selection_anchor'
require_relative 'reader/intent_runtime_bridge'
require_relative 'reader/runtime_types'
require_relative 'reader/runtime_setup'
require_relative 'reader/state_observer'
require_relative 'reader/progress_autosave'
require_relative 'reader/toc_anchor_resolver'
require_relative 'reader/inline_link_navigator'

require_relative 'reader/input_router'
require_relative 'reader/event_loop'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Coordinator class for the reading experience.
        #
        # This is the whole reader: navigation, rendering, and the mouse state
        # machine (text selection, the right-click context menu, inline-link
        # hover, and the bar-anchored overlay routing) live here as one host.
        # Mouse behavior shares this object's selection state — @selected_text,
        # @suppress_popup_release_once — and its dependency graph, so it is not
        # a separable collaborator (constitution R1: behavior bound to one
        # host's state belongs on the host; R2: length is never a reason to
        # split).
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

          # Synthesised keys the overlay mouse router replays onto the active
          # mode's existing bindings.
          OVERLAY_SCROLL_UP_KEY = "\e[A"
          OVERLAY_SCROLL_DOWN_KEY = "\e[B"
          OVERLAY_ACTIVATE_KEY = "\r"
          OVERLAY_DISMISS_KEY = "\e"

          # The reader-state field holding each overlay's selection cursor, written
          # before the activate key so ⏎ confirms the clicked row.
          BAR_OVERLAY_INDEX_FIELDS = {
            in_book_search: :search_selected_index,
            dictionary: :dictionary_selected_index,
            toc: :toc_selected_index,
            translator: :translator_picker_index,
            notes: :notes_selected_index,
          }.freeze

          # Overlay click targets that are buttons (not list rows) and light up
          # under the pointer like a row does.
          HOVERABLE_OVERLAY_ACTIONS = %i[paste_source copy_translation translator_close].freeze

          # Symbol hit-targets that re-enter the use-case layer as a translator intent
          # (the mouse equivalent of Tab / a typed action), mapped to their args.
          OVERLAY_CLICK_INTENTS = {
            picker_source: %i[translator_open_picker source],
            picker_target: %i[translator_open_picker target],
            paste_source: %i[translator_paste_source],
            copy_translation: %i[translator_copy_translation],
          }.freeze

          # The state accessor for each overlay's render component (which owns the
          # frame's hit geometry).
          BAR_OVERLAY_POPUPS = {
            in_book_search: :in_book_search_popup,
            dictionary: :dictionary_lookup_popup,
            toc: :toc_lookup_popup,
            translator: :translator_lookup_popup,
            notes: :notes_lookup_popup,
          }.freeze

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
            @render_pending = false
            @services = Reader::RuntimeTypes.services_for(core)
            @references = Reader::RuntimeTypes.references_for(core: core, state: state, services: services)
            assign_service_references(@references)
            assign_state_references(@references)
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
            @render_pending = true
            terminal_service.wake_input
            nil
          end

          # True once per render-request burst; the event loop redraws and the
          # next blocking read resumes.
          def consume_render_request?
            pending = @render_pending
            @render_pending = false
            pending == true
          end

          # Relays carrying async results (e.g. translations) back to the UI
          # thread; registered during composition, drained by the event loop.
          def register_async_relay(relay)
            (@async_relays ||= []) << relay
          end

          def drain_async_results
            Array(@async_relays).sum(&:drain!)
          end

          def async_work_pending?
            Array(@async_relays).any?(&:busy?)
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
            @reader_session_mutator.update_reader(popup_menu: nil, hovered_inline_link: nil)
            @mouse_handler&.reset
            @reader_session_mutator.clear_selection
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
            @reader_session_mutator.update_reader(popup_menu: nil, hovered_inline_link: nil)
            @selected_text = nil
            @reader_session_mutator.clear_selection
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
            mode = active_bar_overlay_mode
            return false unless mode

            if wheel_event?(event)
              feed_overlay_key(wheel_up?(event) ? OVERLAY_SCROLL_UP_KEY : OVERLAY_SCROLL_DOWN_KEY)
            elsif motion_event?(event)
              update_overlay_hover(mode, event)
            elsif left_press?(event)
              move_overlay_selection(mode, event)
            elsif left_release?(event)
              activate_overlay_click(mode, event)
            end
            true
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

          # The active bar-overlay mode, or nil when the reader is in normal
          # reading/selection (the annotation editor and the right-click context
          # menu keep their own existing mouse handling).
          def active_bar_overlay_mode
            mode = @reader_state_reader&.mode
            BAR_OVERLAY_INDEX_FIELDS.key?(mode) ? mode : nil
          end

          # SGR wheel reports set bit 6; bit 0 is direction (up=0/down=1) and bit 1
          # marks the horizontal wheel, which we ignore.
          def wheel_event?(event)
            button = event[:button].to_i
            button.allbits?(0x40) && button.nobits?(0x02)
          end

          def wheel_up?(event)
            event[:button].to_i.nobits?(0x01)
          end

          # Pointer-motion report (bit 5), with or without a button held — drives
          # the hover preview.
          def motion_event?(event)
            event[:button].to_i.allbits?(0x20)
          end

          # A left-button press (low bits 0, no motion/wheel bits, not a release).
          def left_press?(event)
            !event[:released] && event[:button].to_i.nobits?(0x63)
          end

          # A left-button release (low bits 0, not a wheel report).
          def left_release?(event)
            event[:released] && event[:button].to_i.nobits?(0x43)
          end

          # Hover preview: light up the row — or the Paste/Copy button — under the
          # pointer (or clear it when off them). The hover target is the row index
          # or the action symbol; only writes/redraws when it actually changes.
          def update_overlay_hover(mode, event)
            target = overlay_hit_target_for_event(mode, event)
            hover = overlay_hover_value(target)
            return if hover == @reader_state_reader&.overlay_hover_index

            @reader_session_mutator.update_reader(overlay_hover_index: hover)
            draw_screen
          end

          def overlay_hover_value(target)
            return target if target.is_a?(Integer)
            return target if HOVERABLE_OVERLAY_ACTIONS.include?(target)

            nil
          end

          # Press moves the real selection cursor to the row under the pointer
          # (and drops the hover preview, since the row is now selected).
          def move_overlay_selection(mode, event)
            target = overlay_hit_target_for_event(mode, event)
            return unless target.is_a?(Integer)

            @reader_session_mutator.update_reader(
              BAR_OVERLAY_INDEX_FIELDS.fetch(mode) => target, overlay_hover_index: nil
            )
            draw_screen
          end

          # Release activates: confirm the row under the pointer (⏎), re-enter a
          # translator affordance (open/flip the picker, Paste, Copy), close the
          # translator from its red box, or dismiss the overlay when the release lands
          # in the book above it (Esc — but never for the translator, which closes
          # only from its box or Esc).
          def activate_overlay_click(mode, event)
            target = overlay_hit_target_for_event(mode, event)
            return activate_overlay_row(mode, target) if target.is_a?(Integer)
            return dismiss_overlay if target == :translator_close
            return dismiss_overlay if target == :outside && mode != :translator

            intent = OVERLAY_CLICK_INTENTS[target]
            dispatch_overlay_intent(*intent) if intent
          end

          def activate_overlay_row(mode, index)
            @reader_session_mutator.update_reader(
              BAR_OVERLAY_INDEX_FIELDS.fetch(mode) => index, overlay_hover_index: nil
            )
            feed_overlay_key(OVERLAY_ACTIVATE_KEY)
          end

          # Esc through the same path keys take: from the translator's editor face
          # this closes it outright. The translator no longer dismisses on a click out
          # in the book — only its red close box (or Esc) closes it — so the book stays
          # put while you reach for the Paste button or the language tabs.
          def dismiss_overlay
            @reader_session_mutator.update_reader(overlay_hover_index: nil)
            feed_overlay_key(OVERLAY_DISMISS_KEY)
          end

          # Clicking a translator affordance (the source/target language label, or
          # the Paste/Copy button) re-enters the use-case layer with that intent —
          # the mouse equivalent of Tab / a typed action.
          def dispatch_overlay_intent(intent, payload = nil)
            @reader_session_mutator.update_reader(overlay_hover_index: nil)
            input_controller&.dispatch_reader_intent(intent, payload)
            draw_screen
          end

          def overlay_hit_target_for_event(mode, event)
            coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])
            component = bar_overlay_component(mode)
            return :inside unless component

            component.hit_test(coords[:x], coords[:y])
          end

          def bar_overlay_component(mode)
            accessor = BAR_OVERLAY_POPUPS.fetch(mode)
            @reader_state_reader&.public_send(accessor)
          end

          # Replay a synthesised key through the same dispatch path real keys take,
          # then repaint so the result is immediately visible.
          def feed_overlay_key(key)
            dispatch_input_keys([key])
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
              logger: @logger
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
            popup_ui_controller&.translator_visible? == true
          end

          def popup_menu_active?
            @reader_state_reader.popup_menu&.visible
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
            return false unless Shoko::Shared::Terminal::MouseButton.right_click_press?(event)

            context = popup_context_click_data(event)
            return false unless context

            popup_menu = open_popup_menu(anchor_position: context[:anchor_position])
            @suppress_popup_release_once = true if popup_menu
            !popup_menu.nil?
          end

          def open_popup_menu(anchor_position: nil)
            popup_menu = build_popup_menu(anchor_position: anchor_position)
            return nil unless popup_menu

            @reader_session_mutator.update_reader(popup_menu: popup_menu, popup_menu_selected: 0)
            return nil unless popup_menu.visible

            activate_popup_menu
            popup_menu
          end

          def build_popup_menu(anchor_position: nil)
            selection = @reader_state_reader.selection
            return nil unless selection

            rendered = popup_rendered_lines
            factory = @ui_component_factory
            return nil unless factory

            factory.enhanced_popup_menu(**popup_menu_args(selection, rendered, anchor_position))
          end

          def popup_menu_args(selection, rendered, anchor_position)
            {
              selection: selection,
              coordinate_service: @coordinate_service,
              reader_state_reader: @reader_state_reader,
              reader_session_mutator: @reader_session_mutator,
              popup_position_service: @popup_position_service,
              clipboard_service: clipboard_service,
              rendered: rendered,
              dictionary_enabled: dictionary_lookup_available?,
              anchor_position: anchor_position,
            }
          end

          def activate_popup_menu
            switch_mode(:popup_menu)
            draw_screen
          end

          def popup_context_click_data(event)
            selection = @reader_state_reader.selection
            rendered = popup_rendered_lines
            return nil unless selection && rendered

            click_anchor = popup_click_anchor(event, rendered)
            return nil unless click_anchor && anchor_within_selection?(click_anchor, selection, rendered)
            return nil unless popup_selected_text(selection)

            { anchor_position: @coordinate_service.mouse_to_terminal(event[:x], event[:y]) }
          end

          def popup_rendered_lines
            rendered = @rendered_content_reader&.rendered_lines
            return nil if rendered.nil? || rendered.empty?

            rendered
          end

          def popup_click_anchor(event, rendered)
            @coordinate_service.anchor_from_point({ x: event[:x], y: event[:y] }, rendered, bias: :nearest)
          end

          def popup_selected_text(selection)
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

          def dictionary_lookup_available?
            dict_avail = @dictionary_availability
            return false unless dict_avail
            return false unless dict_avail.sqlite3_available?

            backend = @config_reader.dictionary_backend
            return false if backend.to_s.downcase == 'disabled'

            true
          end

          def handle_selection_end
            update_state_selection(@mouse_handler.selection_range)
            selection = @reader_state_reader.selection
            return unless selection

            @selected_text = extract_selected_text(selection)
            return if @selected_text && !@selected_text.strip.empty?

            @mouse_handler.reset
            @reader_session_mutator.clear_selection
          end

          def extract_selected_text(range)
            selection_service = @selection_service
            content_reader = @rendered_content_reader
            return nil unless selection_service && content_reader

            selection_service.extract_text(range, content_reader.rendered_lines)
          end

          def update_state_selection(mouse_range)
            anchor_range = anchor_range_from_mouse(mouse_range)
            if anchor_range
              @reader_session_mutator.update_reader(selection: anchor_range)
            else
              @reader_session_mutator.clear_selection
            end
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

# Required after the class body so the collaborators can reopen ReaderController
# and nest under it (they are part of this reader's mouse state machine).
require_relative 'reader_controller/input_sequence_filter'
require_relative 'reader_controller/inline_link_interaction'
