# frozen_string_literal: true

require 'forwardable'
require_relative '../../../shared/errors'

require_relative '../../../application/reader_lifecycle'

require_relative '../../../application/services/document_path_resolver'

require_relative '../../../application/services/pagination/pagination_coordinator'

require_relative '../../../application/pending_jump_handler'

require_relative 'dependencies/reader_controller_dependencies'

require_relative 'reader/runtime_bootstrap'
require_relative 'reader/input_router'
require_relative 'reader/startup_loader'
require_relative 'reader/render_metrics'
require_relative 'reader/event_loop'

module Shoko
  module Adapters::Input
    module Controllers
      # Coordinator class for the reading experience.
      class ReaderController
        extend Forwardable
        include Application::Services::DocumentPathResolver

        # Core runtime context for the reader.
        Context = Struct.new(:path, :doc, :metrics_start_time, :memo, keyword_init: true)
        # Service references used across the reader lifecycle.
        Services = Struct.new(:page_calculator, :terminal_service, :clipboard_service, :instrumentation,
                              keyword_init: true)
        # Group UI/state/input controllers for delegation.
        ControllerRefs = Struct.new(:ui_controller, :state_controller, :input_controller, keyword_init: true)
        # Group lifecycle/render/pagination coordinators for delegation.
        Coordinators = Struct.new(:lifecycle, :pagination_coordinator, :render_coordinator, keyword_init: true)

        attr_reader :context, :services, :controllers, :coordinators, :observer_registry

        def_delegators :context, :path, :doc, :metrics_start_time
        def_delegators :services, :page_calculator, :terminal_service, :clipboard_service, :instrumentation
        def_delegators :controllers, :ui_controller, :state_controller, :input_controller
        def_delegators :coordinators, :lifecycle, :pagination_coordinator, :render_coordinator

        # Service accessors for commands and collaborators
        attr_reader :navigation_service_ref, :bookmark_service_ref, :popup_position_service_ref,
                    :logger_ref, :command_bus_ref, :process_control_ref
        attr_reader :reader_state_reader, :state_writer

        def navigation_service
          @navigation_service_ref
        end

        def bookmark_service
          @bookmark_service_ref
        end

        def popup_position_service
          @popup_position_service_ref
        end

        def logger
          @logger_ref
        end

        def command_bus
          @command_bus_ref
        end

        def process_control
          @process_control_ref
        end

        def_delegators :ui_controller, :switch_mode, :open_toc, :open_bookmarks, :open_annotations_tab,
                       :open_annotations,
                       :show_help, :toggle_view_mode, :increase_line_spacing, :decrease_line_spacing,
                       :toggle_page_numbering_mode, :sidebar_down, :sidebar_up, :sidebar_select,
                       :handle_popup_action, :close_dictionary,
                       :dictionary_insert_char, :dictionary_backspace, :dictionary_confirm, :dictionary_cancel,
                       :dictionary_tab, :dictionary_swap_languages,
                       :dictionary_scroll_up, :dictionary_scroll_down,
                       :dictionary_toggle_fuzzy, :dictionary_cycle_result,
                       :dictionary_cycle_pair, :open_in_book_search, :close_in_book_search,
                       :in_book_search_insert_char, :in_book_search_backspace, :in_book_search_confirm,
                       :in_book_search_cancel, :in_book_search_up, :in_book_search_down

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

        def initialize(epub_path, deps:)
          deps.validate!

          @context = Context.new(path: epub_path,
                                 doc: nil,
                                 metrics_start_time: nil,
                                 memo: {})

          @services = Services.new(
            page_calculator: deps.page_calculator,
            terminal_service: deps.terminal_service,
            clipboard_service: deps.clipboard_service,
            instrumentation: deps.instrumentation
          )

          @navigation_service_ref = deps.navigation_service
          @bookmark_service_ref = deps.bookmark_service
          @popup_position_service_ref = deps.popup_position_service
          @logger_ref = deps.logger
          @command_bus_ref = deps.command_bus
          @process_control_ref = deps.process_control
          @clock_ref = deps.clock
          @key_classifier = deps.key_classifier
          @selection_service_ref = deps.selection_service
          @wrapping_service_ref = deps.wrapping_service
          @rendered_content_reader = deps.rendered_content_reader
          @annotation_service_ref = deps.annotation_service
          @render_registry_ref = deps.render_registry
          @document_service_factory = deps.document_service_factory
          @coordinate_service_ref = deps.coordinate_service
          @reader_state_reader = deps.reader_state_reader
          @state_writer = deps.state_writer
          @config_reader = deps.config_reader
          @reader_session_context = deps.reader_session_context
          @observer_registry = deps.observer_registry

          lifecycle = Application::ReaderLifecycle.new(self,
                                          terminal_service: deps.terminal_service,
                                          background_worker: deps.background_worker,
                                          background_worker_factory: deps.background_worker_factory,
                                          async_executor: deps.async_executor,
                                          instrumentation_service: deps.instrumentation_service,
                                          pagination_cache_preloader: deps.pagination_cache_preloader)
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
          @context.doc = @startup_loader.validate_preloaded_document(deps.document, target_path)
          load_document unless doc
          @reader_session_context.document = doc if @reader_session_context && doc
          @state_writer.update_selections(book_path: epub_path)

          runtime_deps = deps.to_runtime_bootstrap_dependencies(doc: doc)

          bootstrap = Reader::RuntimeBootstrap.new(deps: runtime_deps).build(reader_controller: self)

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
            instrumentation: deps.instrumentation,
            metrics_start_time_reader: -> { metrics_start_time },
            document_reader: -> { doc },
            clock: @clock_ref
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
            begin
              pagination_coordinator.sync_sidebar_layout(sidebar_visible: _new_value == true)
            rescue StandardError
              nil
            end
            rebuild_root_layout
            force_redraw
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

        # Explicit public contract for collaborators to clear transient selection state.
        def clear_active_selection
          clear_selection!
        end

        def annotation_editor_active?
          @input_router.annotation_editor_active?
        end

        # Remove all observer registrations created during this reader session.
        # Prevents stale callbacks from firing after the session ends.
        def cleanup_observers
          @observer_registry&.remove_observer(self)
          render_coordinator&.cleanup_observers
        rescue StandardError => e
          @logger_ref&.debug('reader_controller.cleanup_observers_failed',
                             error: e.class.name, message: e.message)
        end

        # Main application loop
        def main_loop
          Reader::EventLoop.new(self, @reader_state_reader, metrics_start_time, instrumentation, clock: @clock_ref).run
        end

        def mark_metrics_start!
          context.metrics_start_time = monotonic_now
        end

        private

        def memo
          context.memo ||= {}
        end

        def monotonic_now
          @clock_ref.monotonic_now
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
          memo[:jump_handler] ||= Application::PendingJumpHandler.new(
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

        def current_editor_component
          @reader_state_reader.annotation_editor_overlay
        end

        # Ensure both UI state and any local selection handlers are cleared
        def cleanup_popup_state
          ui_controller.cleanup_popup_state
          clear_selection!
        end

        public :current_editor_component
      end
    end
  end
end
