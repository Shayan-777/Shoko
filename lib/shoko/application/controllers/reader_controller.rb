# frozen_string_literal: true

require 'forwardable'
# Legacy reader modes removed; TOC/bookmarks live in the sidebar.
require_relative '../../adapters/output/ui/constants/ui_constants'
require_relative '../../shared/errors'
require_relative '../../adapters/output/ui/constants/messages'
require_relative '../annotation_editor_overlay_session'
require_relative '../reader_lifecycle'
require_relative '../../adapters/output/ui/rendering/reader_render_coordinator'
require_relative '../../core/services/pagination/pagination_coordinator'
require_relative '../../adapters/input/dispatcher'
require_relative '../../adapters/output/ui/rendering/frame_coordinator'
require_relative '../../adapters/output/ui/rendering/render_pipeline'
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
      # - Adapters::Input::InputController: handles all input processing
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
        include Shoko::Adapters::Output::Ui::Constants::UI
        # Helpers::ReaderHelpers removed; wrapping is provided by DI-backed WrappingService
        include Shoko::Adapters::Input::KeyDefinitions::Helpers

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

        # Navigation is handled via Core::Services::NavigationService through input commands

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

        def initialize(epub_path, _config = nil, dependencies = nil)
          deps = dependencies || Application::ContainerFactory.create_default_container
          state_store = deps.resolve(:global_state)
          @context = Context.new(path: epub_path,
                                 dependencies: deps,
                                 state: state_store,
                                 doc: nil,
                                 metrics_start_time: nil,
                                 memo: {})
          @services = Services.new(
            page_calculator: deps.resolve(:page_calculator),
            terminal_service: deps.resolve(:terminal_service),
            clipboard_service: deps.resolve(:clipboard_service),
            instrumentation: resolve_optional(:instrumentation_service)
          )
          lifecycle = ReaderLifecycle.new(self,
                                          dependencies: deps,
                                          terminal_service: terminal_service)
          @coordinators = Coordinators.new(lifecycle: lifecycle,
                                           pagination_coordinator: nil,
                                           render_coordinator: nil)
          lifecycle.ensure_background_worker

          # Load document before creating controllers that depend on it
          @context.doc = preload_document_from_dependencies
          load_document unless doc
          # Expose current book path in state for downstream services/screens
          state.dispatch(Shoko::Application::Actions::UpdateSelectionsAction.new(book_path: path))

          # Initialize focused controllers with proper dependencies including document
          ui = UIController.new(state, deps)
          sc = StateController.new(state, doc, epub_path, deps)
          input = Shoko::Adapters::Input::InputController.new(state, deps)
          @controllers = ControllerRefs.new(ui_controller: ui,
                                            state_controller: sc,
                                            input_controller: input)

          # Register controllers in the dependency container for components that resolve them
          deps.register(:ui_controller, ui)
          deps.register(:state_controller, sc)
          deps.register(:input_controller, input)
          # Expose reader controller for components/controllers needing cleanup hooks
          deps.register(:reader_controller, self)

          frame_coordinator = Shoko::Adapters::Output::Ui::Rendering::FrameCoordinator.new(deps)
          render_pipeline = Shoko::Adapters::Output::Ui::Rendering::RenderPipeline.new(deps)
          pagination = Core::Services::Pagination::PaginationCoordinator.new(
            state: state,
            doc: doc,
            page_calculator: page_calculator,
            layout_service: deps.resolve(:layout_service),
            terminal_service: terminal_service,
            pagination_cache: resolve_optional(:pagination_cache),
            frame_coordinator: frame_coordinator,
            ui_controller: ui,
            render_callback: lambda {
              force_redraw
              draw_screen
            },
            background_worker_provider: -> { background_worker },
            config_reader: deps.resolve(:config_reader),
            state_writer: deps.resolve(:state_writer)
          )
          render = Shoko::Adapters::Output::Ui::Rendering::ReaderRenderCoordinator.new(
            dependencies: Shoko::Adapters::Output::Ui::Rendering::ReaderRenderCoordinator::Dependencies.new(
              controller: self,
              state: state,
              dependencies: deps,
              terminal_service: terminal_service,
              frame_coordinator: frame_coordinator,
              render_pipeline: render_pipeline,
              ui_controller: ui,
              wrapping_service: wrapping_service,
              pagination: pagination,
              doc: doc
            )
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
          # This guards against any state synchronization issues between menu and reader
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
          panel_visible = panel&.respond_to?(:visible?) && panel.visible?
          popup_visible = popup&.respond_to?(:visible?) && popup.visible?
          panel_visible || popup_visible
        end

        def cancel_key_pressed?(keys)
          Array(keys).any? { |key| Shoko::Adapters::Input::KeyDefinitions::ACTIONS[:cancel].include?(key) }
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

        def resolve_optional(service_name)
          return dependencies.resolve(service_name) if dependencies.registered?(service_name)

          nil
        rescue StandardError
          nil
        end

        def memo
          context.memo ||= {}
        end

        def selection_service
          return memo[:selection_service] if memo.key?(:selection_service)

          memo[:selection_service] = begin
            dependencies.resolve(:selection_service)
          rescue StandardError
            nil
          end
        end

        def wrapping_service
          return memo[:wrapping_service] if memo.key?(:wrapping_service)

          memo[:wrapping_service] =
            (dependencies.resolve(:wrapping_service) if dependencies.registered?(:wrapping_service))
        rescue StandardError
          memo[:wrapping_service] = nil
        end

        def preload_document_from_dependencies
          return nil unless dependencies.respond_to?(:registered?) && dependencies.registered?(:document)

          dependencies.resolve(:document)
        rescue StandardError
          nil
        end

        def load_document
          return doc if doc

          factory = dependencies.resolve(:document_service_factory)
          document_service = factory.call(path)
          @context.doc = document_service.load_document

          # Register document in dependency container for services to access
          dependencies.register(:document, doc)
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

        def load_data
          state_controller.load_progress
          state_controller.load_bookmarks
          state_controller.refresh_annotations
        end

        def apply_pending_jump_if_present
          jump_handler.apply
        end

        def jump_handler
          memo[:jump_handler] ||= PendingJumpHandler.new(state, dependencies, ui_controller)
        end

        def normalize_selection_for_state(range)
          service = selection_service
          return nil unless service

          rendered_content_reader = dependencies.resolve(:rendered_content_reader)
          service.normalize_range(rendered_content_reader: rendered_content_reader, selection_range: range)
        end

        def read_input_keys(timeout: nil)
          terminal_service.read_keys_blocking(limit: 10, timeout: timeout)
        end

        # Override helper to delegate to the DI-backed wrapping service
        def wrap_lines(lines, width)
          service = wrapping_service
          if service
            chapter_index = state&.get(%i[reader current_chapter]) || 0
            return service.wrap_lines(lines, chapter_index, width)
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
            dependencies,
            ui_controller
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
              keys = if notification_active
                       controller.read_input_keys(timeout: NOTIFICATION_POLL_INTERVAL)
                     else
                       controller.read_input_keys
                     end
              record_tti(startup_reference, keys)
              if keys.empty?
                controller.draw_screen if notification_active
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

          def log_debug(event, **data)
            logger = controller.dependencies.resolve(:logger)
            logger&.debug(event, **data)
          rescue StandardError
            # Silently ignore logging failures
          end
        end
      end
    end
  end
end
