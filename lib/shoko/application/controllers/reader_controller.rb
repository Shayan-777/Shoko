# frozen_string_literal: true

require 'forwardable'
require_relative '../../shared/errors'
require_relative '../annotation_editor_overlay_session'
require_relative '../reader_lifecycle'
require_relative 'document_path_resolver'
require_relative '../../core/services/pagination/pagination_coordinator'
require_relative '../pending_jump_handler'

module Shoko
  module Application
    module Controllers
      # Coordinator class for the reading experience.
      #
      # This refactored ReaderController now delegates responsibilities to focused controllers/services:
      # - Core::Services::NavigationService: handles page/chapter navigation (via input bindings)
      # - UIController: handles mode switching and UI state
      # - StateController: handles persistence and state management
      # - InputController: handles all input processing (via :input_system_factory port)
      #
      # The ReaderController now focuses only on:
      # - Component layout and rendering coordination
      # - Controller coordination and delegation
      # - Main application loop
      #
      # @attr_reader doc [EPUBDocument] The loaded EPUB document.
      # @attr_reader state [Application::Infrastructure::ObserverStateStore] The current state of the reader.
      class ReaderController
        extend Forwardable
        include DocumentPathResolver

        # Core runtime context for the reader.
        Context = Struct.new(:path, :dependencies, :state, :doc, :metrics_start_time, :memo, keyword_init: true)
        # Service references used across the reader lifecycle.
        Services = Struct.new(:page_calculator, :terminal_service, :clipboard_service, :instrumentation,
                              keyword_init: true)
        # Group UI/state/input controllers for delegation.
        ControllerRefs = Struct.new(:ui_controller, :state_controller, :input_controller, keyword_init: true)
        # Group lifecycle/render/pagination coordinators for delegation.
        Coordinators = Struct.new(:lifecycle, :pagination_coordinator, :render_coordinator, keyword_init: true)

        attr_reader :context, :services, :controllers, :coordinators

        def_delegators :context, :path, :dependencies, :state, :doc, :metrics_start_time
        def_delegators :services, :page_calculator, :terminal_service, :clipboard_service, :instrumentation
        def_delegators :controllers, :ui_controller, :state_controller, :input_controller
        def_delegators :coordinators, :lifecycle, :pagination_coordinator, :render_coordinator

        # Service accessors for commands and collaborators
        attr_reader :navigation_service_ref, :bookmark_service_ref, :logger_ref

        def navigation_service
          @navigation_service_ref
        end

        def bookmark_service
          @bookmark_service_ref
        end

        def logger
          @logger_ref
        end

        def_delegators :ui_controller, :switch_mode, :open_toc, :open_bookmarks, :open_annotations_tab,
                       :open_annotations,
                       :show_help, :toggle_view_mode, :increase_line_spacing, :decrease_line_spacing,
                       :toggle_page_numbering_mode, :sidebar_down, :sidebar_up, :sidebar_select,
                       :handle_popup_action, :close_dictionary, :handle_dictionary_key,
                       :dictionary_scroll_up, :dictionary_scroll_down,
                       :dictionary_toggle_fuzzy, :dictionary_cycle_result,
                       :dictionary_cycle_pair

        def_delegators :state_controller, :save_progress, :load_progress, :load_bookmarks,
                       :add_bookmark, :jump_to_bookmark, :delete_selected_bookmark, :quit_to_menu,
                       :quit_application

        def_delegators :input_controller, :handle_popup_navigation, :handle_popup_action_key,
                       :handle_popup_cancel, :handle_popup_menu_input

        def_delegators :render_coordinator, :draw_screen, :refresh_highlighting, :force_redraw,
                       :render_loading_overlay, :build_component_layout, :rebuild_root_layout,
                       :apply_theme_palette

        def_delegators :pagination_coordinator, :pending_initial_calculation?,
                       :perform_initial_calculations_if_needed, :defer_page_map?,
                       :schedule_background_page_map_build, :clear_defer_page_map!,
                       :rebuild_pagination, :invalidate_pagination_cache

        def_delegators :lifecycle, :run, :background_worker

        def initialize(epub_path, container:, state:, terminal_service:,
                       page_calculator:, clipboard_service:, instrumentation: nil,
                       navigation_service: nil, bookmark_service: nil,
                       key_classifier: nil, selection_service: nil,
                       wrapping_service: nil, rendered_content_reader: nil,
                       annotation_service: nil, render_registry: nil,
                       document_service_factory: nil, coordinate_service: nil,
                       layout_service:, rendering_factory:, input_system_factory:,
                       notification_service: nil, ui_component_factory: nil,
                       layout_metrics: nil, dictionary_service: nil,
                       settings_service: nil, dictionary_availability: nil,
                       background_worker: nil, background_worker_factory: nil,
                       progress_repository: nil, bookmark_repository: nil,
                       pagination_cache: nil, notification_writer: nil,
                       async_executor: nil, display_capabilities: nil,
                       config_reader:, reader_state_reader:, state_writer:,
                       instrumentation_service: nil,
                       pagination_cache_preloader: nil,
                       document: nil, logger: nil)
          @container = container
          @context = Context.new(path: epub_path,
                                 dependencies: container,
                                 state: state,
                                 doc: nil,
                                 metrics_start_time: nil,
                                 memo: {})

          @services = Services.new(
            page_calculator: page_calculator,
            terminal_service: terminal_service,
            clipboard_service: clipboard_service,
            instrumentation: instrumentation
          )

          @navigation_service_ref = navigation_service
          @bookmark_service_ref = bookmark_service
          @logger_ref = logger
          @key_classifier = key_classifier
          @selection_service_ref = selection_service
          @wrapping_service_ref = wrapping_service
          @rendered_content_reader = rendered_content_reader
          @annotation_service_ref = annotation_service
          @render_registry_ref = render_registry
          @document_service_factory = document_service_factory
          @coordinate_service_ref = coordinate_service

          lifecycle = ReaderLifecycle.new(self,
                                          terminal_service: terminal_service,
                                          background_worker: background_worker,
                                          background_worker_factory: background_worker_factory,
                                          async_executor: async_executor,
                                          instrumentation_service: instrumentation_service,
                                          pagination_cache_preloader: pagination_cache_preloader)
          @coordinators = Coordinators.new(lifecycle: lifecycle,
                                           pagination_coordinator: nil,
                                           render_coordinator: nil)
          lifecycle.ensure_background_worker

          # Load document before creating controllers that depend on it
          @context.doc = validate_preloaded_document(document)
          load_document unless doc
          # Expose current book path in state for downstream services/screens
          state.dispatch(Shoko::Application::Actions::UpdateSelectionsAction.new(book_path: epub_path))

          # Initialize focused controllers with proper dependencies including document
          ui = UIController.new(
            state: state,
            notification_service: notification_service,
            selection_service: selection_service,
            rendered_content_reader: rendered_content_reader,
            clipboard_service: clipboard_service,
            ui_component_factory: ui_component_factory,
            input_controller: nil, # will be set after input controller is created
            reader_controller: self,
            state_controller: nil, # will be set after state controller is created
            annotation_service: annotation_service,
            dictionary_service: dictionary_service,
            terminal_service: terminal_service,
            layout_metrics: layout_metrics,
            layout_service: layout_service,
            document: doc,
            navigation_service: navigation_service,
            bookmark_service: bookmark_service,
            render_registry: render_registry,
            settings_service: settings_service,
            logger: logger,
            dictionary_availability: dictionary_availability,
            formatting_service: container.resolve_optional(:formatting_service),
            config_reader: config_reader
          )
          sc = StateController.new(
            state: state,
            doc: doc,
            path: epub_path,
            terminal_service: terminal_service,
            progress_repository: progress_repository,
            bookmark_repository: bookmark_repository,
            annotation_service: annotation_service,
            logger: logger,
            navigation_service: navigation_service,
            page_calculator: page_calculator,
            layout_service: layout_service,
            bookmark_service: bookmark_service,
            notification_service: notification_service,
            coordinate_service: coordinate_service,
            render_registry: render_registry
          )
          input = input_system_factory.create_reader_input_controller(state, container)
          @controllers = ControllerRefs.new(ui_controller: ui,
                                            state_controller: sc,
                                            input_controller: input)

          # Resolve circular dependency: UIController was created before
          # InputController and StateController existed — inject them now.
          ui.input_controller = input
          ui.state_controller = sc

          # Register sub-objects in container for adapter-level subsystems that resolve them
          container.register(:ui_controller, ui)
          container.register(:state_controller, sc)
          container.register(:input_controller, input)
          container.register(:reader_controller, self)

          frame_coordinator = rendering_factory.create_frame_coordinator(container)
          render_pipeline = rendering_factory.create_render_pipeline(container)
          pagination = Core::Services::Pagination::PaginationCoordinator.new(
            doc: doc,
            page_calculator: page_calculator,
            layout_service: layout_service,
            terminal_service: terminal_service,
            pagination_cache: pagination_cache,
            frame_coordinator: frame_coordinator,
            notification_writer: notification_writer,
            logger: logger,
            render_callback: lambda {
              force_redraw
              draw_screen
            },
            async_executor: async_executor,
            display_capabilities: display_capabilities,
            instrumentation: instrumentation,
            config_reader: config_reader,
            reader_state_reader: reader_state_reader,
            state_writer: state_writer
          )
          render = rendering_factory.create_reader_render_coordinator(
            dependencies: container,
            state: state,
            controller: self,
            terminal_service: terminal_service,
            frame_coordinator: frame_coordinator,
            render_pipeline: render_pipeline,
            ui_controller: ui,
            wrapping_service: wrapping_service,
            pagination: pagination,
            doc: doc
          )
          @coordinators.pagination_coordinator = pagination
          @coordinators.render_coordinator = render

          apply_theme_palette

          # Do not load saved data synchronously to keep first paint fast.
          # Pending jump application will occur after progress load in run.
          apply_pending_jump_if_present

          # Build UI components
          build_component_layout
          input_controller.setup_input_dispatcher(self)

          # Ensure running flag is explicitly set before event loop starts
          state.dispatch(Shoko::Application::Actions::UpdateReaderMetaAction.new(running: true))

          # Observe sidebar visibility changes to rebuild layout
          state.add_observer(self, %i[reader sidebar_visible], %i[reader dictionary_visible],
                             %i[reader dictionary_panel], %i[config theme],
                             %i[config view_mode], %i[config line_spacing],
                             %i[config page_numbering_mode],
                             %i[config kitty_images])
        end

        # Observer callback for state changes
        def state_changed(path, _old_value, _new_value)
          case path
          when %i[reader sidebar_visible]
            rebuild_root_layout
          when %i[reader dictionary_visible]
            rebuild_root_layout
          when %i[reader dictionary_panel]
            rebuild_root_layout
          when %i[config theme]
            apply_theme_palette
          when %i[config view_mode], %i[config line_spacing], %i[config page_numbering_mode], %i[config kitty_images]
            begin
              pagination_coordinator.rebuild_after_config_change
            rescue StandardError
              # best-effort rebuild; avoid crashing on layout changes
            end
            force_redraw
          end
        end

        def perform_first_paint
          instrumentation&.time('render.first_paint') { draw_screen }
          unless metrics_start_time
            instrumentation&.cancel_trace
            return
          end

          first_paint_completed_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          ttfp = first_paint_completed_at - metrics_start_time
          instrumentation&.record_metric('render.first_paint.ttfp', ttfp, 0)
          instrumentation&.record_trace('render.first_paint.ttfp', ttfp)
          open_type = if doc.respond_to?(:cached?) && doc.cached?
                        'warm'
                      else
                        'cold'
                      end
          instrumentation&.complete_trace(open_type:, total_duration: ttfp)
        end

        def dispatch_input_keys(keys)
          if annotations_overlay_active? && !annotation_editor_visible?
            input_controller.handle_annotations_overlay_input(keys)
          elsif dictionary_visible? && cancel_key_pressed?(keys)
            close_dictionary
          elsif popup_menu_visible?
            input_controller.handle_popup_menu_input(keys)
          else
            keys.each { |key| input_controller.handle_key(key) }
          end
        end

        def annotation_editor_active?
          editor_overlay = Shoko::Application::Selectors::ReaderSelectors.annotation_editor_overlay(state)
          editor_overlay.respond_to?(:visible?) && editor_overlay.visible?
        rescue StandardError
          false
        end

        def annotations_overlay_active?
          overlay = Shoko::Application::Selectors::ReaderSelectors.annotations_overlay(state)
          overlay.respond_to?(:visible?) && overlay.visible?
        end

        def annotation_editor_visible?
          editor_overlay = Shoko::Application::Selectors::ReaderSelectors.annotation_editor_overlay(state)
          editor_overlay.respond_to?(:visible?) && editor_overlay.visible?
        end

        def popup_menu_visible?
          popup_menu = Shoko::Application::Selectors::ReaderSelectors.popup_menu(state)
          popup_menu&.visible
        end

        def dictionary_visible?
          panel = state.get(%i[reader dictionary_panel])
          popup = state.get(%i[reader dictionary_popup])
          panel_visible = panel.respond_to?(:visible?) && panel.visible?
          popup_visible = popup.respond_to?(:visible?) && popup.visible?
          panel_visible || popup_visible
        end

        def cancel_key_pressed?(keys)
          return false unless @key_classifier

          Array(keys).any? { |key| @key_classifier.cancel_key?(key) }
        end

        # Main application loop
        def main_loop
          ReaderEventLoop.new(self, state, metrics_start_time, instrumentation).run
        end

        def mark_metrics_start!
          context.metrics_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        # Page calculation and navigation support
        private

        def memo
          context.memo ||= {}
        end

        def validate_preloaded_document(existing)
          return nil unless existing

          target = canonical_reader_path(path)
          return existing if document_matches_path?(existing, target)

          nil
        rescue StandardError
          nil
        end

        def load_document
          return doc if doc
          raise 'document_service_factory not available' unless @document_service_factory

          document_service = @document_service_factory.call(path)
          @context.doc = document_service.load_document

          # Register document in container for adapter-level subsystems
          @container.register(:document, doc)
          # Expose chapter count for navigation service logic
          begin
            state.dispatch(Shoko::Application::Actions::UpdatePaginationStateAction.new(
                             total_chapters: doc&.chapter_count || 0
                           ))
          rescue StandardError
            # best-effort
          end
          doc
        end

        # canonical_reader_path and document_matches_path? are provided by DocumentPathResolver

        def load_data
          state_controller.load_progress
          state_controller.load_bookmarks
          state_controller.refresh_annotations
        end

        def apply_pending_jump_if_present
          jump_handler.apply
        end

        def jump_handler
          memo[:jump_handler] ||= PendingJumpHandler.new(
            state, nil, ui_controller,
            navigation_service: @navigation_service_ref,
            selection_service: @selection_service_ref,
            rendered_content_reader: @rendered_content_reader,
            coordinate_service: @coordinate_service_ref,
            render_registry: @render_registry_ref
          )
        end

        def normalize_selection_for_state(range)
          return nil unless @selection_service_ref

          @selection_service_ref.normalize_range(
            rendered_content_reader: @rendered_content_reader,
            selection_range: range
          )
        end

        def read_input_keys(timeout: nil)
          terminal_service.read_keys_blocking(limit: 10, timeout: timeout)
        end

        # Override helper to delegate to the DI-backed wrapping service
        def wrap_lines(lines, width)
          if @wrapping_service_ref
            chapter_index = state&.get(%i[reader current_chapter]) || 0
            return @wrapping_service_ref.wrap_lines(lines, chapter_index, width)
          end
          # Fallback (tests/dev only)
          lines
        end

        # Hook for subclasses (MouseableReader) to clear any active selection/popup
        def clear_selection!
          # no-op in base controller
        end

        def activate_annotation_editor_overlay_session
          return memo[:overlay_session] if memo[:overlay_session]

          memo[:overlay_session] = Shoko::Application::AnnotationEditorOverlaySession.new(
            state,
            nil,
            ui_controller,
            annotation_service: @annotation_service_ref
          )
        end

        def deactivate_annotation_editor_overlay_session
          memo[:overlay_session] = nil
        end

        def current_editor_component
          return memo[:overlay_session] if memo[:overlay_session]&.active?

          deactivate_annotation_editor_overlay_session
          ui_controller.current_mode
        end

        # Ensure both UI state and any local selection handlers are cleared
        def cleanup_popup_state
          ui_controller.cleanup_popup_state
          clear_selection!
        end

        # Test helper moved to WrappingService#fetch_window_and_prefetch

        public :activate_annotation_editor_overlay_session,
               :deactivate_annotation_editor_overlay_session,
               :current_editor_component

        # Encapsulates the main reader event loop to tame ReaderController complexity.
        class ReaderEventLoop
          NOTIFICATION_POLL_INTERVAL = 0.1
          BLINK_POLL_INTERVAL = 0.1

          def initialize(controller, state, metrics_start_time, instrumentation)
            @controller = controller
            @state = state
            @metrics_start_time = metrics_start_time
            @instrumentation = instrumentation
            @tti_recorded = false
          end

          def run
            controller.perform_first_paint
            startup_reference = metrics_start_time

            # Debug: Log reader event loop start and running state
            initial_running = running?
            log_debug('reader.event_loop.start', running: initial_running)

            unless initial_running
              log_debug('reader.event_loop.immediate_exit', reason: 'running? was false at loop start')
              return
            end

            while running?
              notification_active = toast_message_active?
              blink_active = annotation_editor_active?
              keys = if notification_active || blink_active
                       controller.read_input_keys(timeout: blink_poll_interval(notification_active))
                     else
                       controller.read_input_keys
                     end
              record_tti(startup_reference, keys)
              if keys.empty?
                controller.draw_screen if notification_active || blink_active
                next
              end

              controller.dispatch_input_keys(keys)
              controller.draw_screen
            end

            log_debug('reader.event_loop.exit', reason: 'running? became false')
          end

          private

          attr_reader :controller, :state, :metrics_start_time, :instrumentation

          def running?
            Shoko::Application::Selectors::ReaderSelectors.running?(state)
          end

          def record_tti(startup_reference, keys)
            return if @tti_recorded
            return unless startup_reference && keys.any?

            instrumentation&.record_metric(
              'render.tti',
              Process.clock_gettime(Process::CLOCK_MONOTONIC) - startup_reference,
              0
            )
            @tti_recorded = true
          end

          def toast_message_active?
            message = Shoko::Application::Selectors::ReaderSelectors.message(state)
            message && !message.to_s.empty?
          rescue StandardError
            false
          end

          def annotation_editor_active?
            controller.annotation_editor_active?
          rescue StandardError
            false
          end

          def blink_poll_interval(notification_active)
            notification_active ? NOTIFICATION_POLL_INTERVAL : BLINK_POLL_INTERVAL
          end

          def log_debug(event, **data)
            controller.logger&.debug(event, **data)
          rescue StandardError
            # Silently ignore logging failures
          end
        end
      end
    end
  end
end
