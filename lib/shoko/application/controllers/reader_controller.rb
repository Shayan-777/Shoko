# frozen_string_literal: true

require 'forwardable'
require_relative '../../shared/errors'
require_relative '../reader_lifecycle'
require_relative 'document_path_resolver'
require_relative '../../core/services/pagination/pagination_coordinator'
require_relative '../pending_jump_handler'
require_relative 'reader/runtime_bootstrap'
require_relative 'reader/input_router'
require_relative 'reader/startup_loader'
require_relative 'reader/render_metrics'
require_relative 'reader/event_loop'
require_relative 'reader/overlay_session_coordinator'

module Shoko
  module Application
    module Controllers
      # Coordinator class for the reading experience.
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
                       page_calculator:, clipboard_service:, layout_service:, rendering_factory:, input_system_factory:, config_reader:, reader_state_reader:, state_writer:, instrumentation: nil,
                       navigation_service: nil, bookmark_service: nil,
                       key_classifier: nil, selection_service: nil,
                       wrapping_service: nil, rendered_content_reader: nil,
                       annotation_service: nil, render_registry: nil,
                       document_service_factory: nil, coordinate_service: nil,
                       notification_service: nil, ui_component_factory: nil,
                       layout_metrics: nil, dictionary_service: nil,
                       dictionary_catalog_service: nil,
                       settings_service: nil, dictionary_availability: nil,
                       formatting_service: nil,
                       background_worker: nil, background_worker_factory: nil,
                       progress_repository: nil, bookmark_repository: nil,
                       pagination_cache: nil, notification_writer: nil,
                       async_executor: nil, display_capabilities: nil,
                       instrumentation_service: nil,
                       pagination_cache_preloader: nil,
                       ui_state_reader: nil, sidebar_state_reader: nil,
                       document: nil, reader_session_context: nil, logger: nil)
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
          @reader_state_reader = reader_state_reader
          @state_writer = state_writer
          @config_reader = config_reader
          @reader_session_context = reader_session_context

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

          @startup_loader = Reader::StartupLoader.new(
            path: epub_path,
            document_service_factory: @document_service_factory,
            reader_session_context: @reader_session_context,
            state_writer: @state_writer,
            document_matches_path: ->(existing, target_path) { document_matches_path?(existing, target_path) },
            logger: @logger_ref
          )

          target_path = canonical_reader_path(path)
          @context.doc = @startup_loader.validate_preloaded_document(document, target_path)
          load_document unless doc
          @reader_session_context.document = doc if @reader_session_context && doc
          @state_writer.update_selections(book_path: epub_path)

          bootstrap = Reader::RuntimeBootstrap.new(
            container: container,
            state: state,
            doc: doc,
            terminal_service: terminal_service,
            page_calculator: page_calculator,
            clipboard_service: clipboard_service,
            layout_service: layout_service,
            rendering_factory: rendering_factory,
            input_system_factory: input_system_factory,
            config_reader: config_reader,
            reader_state_reader: reader_state_reader,
            state_writer: state_writer,
            navigation_service: navigation_service,
            bookmark_service: bookmark_service,
            selection_service: selection_service,
            rendered_content_reader: rendered_content_reader,
            annotation_service: annotation_service,
            render_registry: render_registry,
            coordinate_service: coordinate_service,
            notification_service: notification_service,
            ui_component_factory: ui_component_factory,
            layout_metrics: layout_metrics,
            dictionary_service: dictionary_service,
            dictionary_catalog_service: dictionary_catalog_service,
            settings_service: settings_service,
            dictionary_availability: dictionary_availability,
            formatting_service: formatting_service,
            progress_repository: progress_repository,
            bookmark_repository: bookmark_repository,
            pagination_cache: pagination_cache,
            notification_writer: notification_writer,
            async_executor: async_executor,
            display_capabilities: display_capabilities,
            instrumentation: instrumentation,
            ui_state_reader: ui_state_reader,
            sidebar_state_reader: sidebar_state_reader,
            wrapping_service: wrapping_service,
            logger: logger
          ).build(reader_controller: self)

          @controllers = ControllerRefs.new(
            ui_controller: bootstrap.ui_controller,
            state_controller: bootstrap.state_controller,
            input_controller: bootstrap.input_controller
          )
          @coordinators.pagination_coordinator = bootstrap.pagination_coordinator
          @coordinators.render_coordinator = bootstrap.render_coordinator

          @input_router = Reader::InputRouter.new(
            reader_state_reader: @reader_state_reader,
            input_controller: input_controller,
            ui_controller: ui_controller,
            key_classifier: @key_classifier
          )
          @render_metrics = Reader::RenderMetrics.new(
            instrumentation: instrumentation,
            metrics_start_time_reader: -> { metrics_start_time },
            document_reader: -> { doc }
          )
          @overlay_session_coordinator = Reader::OverlaySessionCoordinator.new(
            ui_controller: ui_controller,
            reader_state: @reader_state_reader,
            state_writer: @state_writer,
            annotation_service: @annotation_service_ref
          )

          apply_theme_palette

          # Do not load saved data synchronously to keep first paint fast.
          # Pending jump application will occur after progress load in run.
          apply_pending_jump_if_present

          # Build UI components
          build_component_layout
          input_controller.setup_input_dispatcher(self)

          # Ensure running flag is explicitly set before event loop starts
          @state_writer.update_reader_meta(running: true)
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
              nil
            end
            force_redraw
          end
        end

        def perform_first_paint
          @render_metrics.perform_first_paint(draw_screen: -> { draw_screen })
        end

        def dispatch_input_keys(keys)
          @input_router.dispatch_input_keys(keys)
        end

        def annotation_editor_active?
          @input_router.annotation_editor_active?
        end

        # Main application loop
        def main_loop
          Reader::EventLoop.new(self, @reader_state_reader, metrics_start_time, instrumentation).run
        end

        def mark_metrics_start!
          context.metrics_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        private

        def memo
          context.memo ||= {}
        end

        def load_document
          loaded = @startup_loader.load_document(current_doc: doc, on_loaded: ->(fresh) { @context.doc = fresh })
          @context.doc = loaded
          loaded
        end

        # canonical_reader_path and document_matches_path? are provided by DocumentPathResolver

        def load_data
          @startup_loader.load_saved_state(state_controller: state_controller)
        end

        def apply_pending_jump_if_present
          @startup_loader.apply_pending_jump(jump_handler: jump_handler)
        end

        def jump_handler
          memo[:jump_handler] ||= PendingJumpHandler.new(
            nil, ui_controller,
            reader_state: @reader_state_reader,
            state_writer: @state_writer,
            rendered_content_reader: @rendered_content_reader,
            navigation_service: @navigation_service_ref,
            selection_service: @selection_service_ref,
            coordinate_service: @coordinate_service_ref
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
            chapter_index = @reader_state_reader&.current_chapter || 0
            return @wrapping_service_ref.wrap_lines(lines, chapter_index, width)
          end

          lines
        end

        # Hook for subclasses (MouseableReader) to clear any active selection/popup
        def clear_selection!
          # no-op in base controller
        end

        def activate_annotation_editor_overlay_session
          @overlay_session_coordinator.activate
        end

        def deactivate_annotation_editor_overlay_session
          @overlay_session_coordinator.deactivate
        end

        def current_editor_component
          @overlay_session_coordinator.current_component
        end

        # Ensure both UI state and any local selection handlers are cleared
        def cleanup_popup_state
          ui_controller.cleanup_popup_state
          clear_selection!
        end

        public :activate_annotation_editor_overlay_session,
               :deactivate_annotation_editor_overlay_session,
               :current_editor_component
      end
    end
  end
end
