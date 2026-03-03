# frozen_string_literal: true

require 'forwardable'
require_relative '../../../shared/errors'
require_relative '../../../shared/text_sanitizer'
require_relative '../../../core/ports/inbound/intent_dispatch_context'
require_relative '../../../core/ports/inbound/reader_intent_handler'
require_relative '../../../core/ports/inbound/input_command_payload'
require_relative '../../../core/ports/inbound/reader_navigation_command_context'
require_relative '../../../core/ports/inbound/reader_bookmark_command_context'

require_relative 'dependencies/reader_controller_dependencies'

require_relative 'reader/input_router'
require_relative 'reader/startup_loader'
require_relative 'reader/render_metrics'
require_relative 'reader/event_loop'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Coordinator class for the reading experience.
        class ReaderController
          extend Forwardable
          include Shoko::Core::Ports::Inbound::IntentDispatchContext
          include Shoko::Core::Ports::Inbound::ReaderNavigationCommandContext
          include Shoko::Core::Ports::Inbound::ReaderBookmarkCommandContext

          # Core runtime context for the reader.
          Context = Struct.new(:path, :doc, :metrics_start_time, :memo, keyword_init: true)
          # Service references used across the reader lifecycle.
          Services = Struct.new(:page_calculator, :terminal_service, :clipboard_service, :instrumentation,
                                keyword_init: true)
          # Group UI/state/input controllers for delegation.
          ControllerRefs = Struct.new(:ui_controller, :state_controller, :input_controller, keyword_init: true)
          # Group lifecycle/render/pagination coordinators for delegation.
          Coordinators = Struct.new(:lifecycle, :pagination_coordinator, :render_coordinator, keyword_init: true)
          # Runtime components assembled by bootstrap composition.
          RuntimeComponents = Struct.new(:ui_controller, :state_controller, :input_controller,
                                         :pagination_coordinator, :render_coordinator, keyword_init: true)

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

          def command_logger
            logger
          end

          def command_bus
            @command_bus_ref
          end

          def process_control
            @process_control_ref
          end

          attr_reader :intent_handler

          def_delegators :ui_controller, :switch_mode, :open_toc, :open_bookmarks, :open_annotations_tab,
                         :open_annotations,
                         :show_help, :toggle_view_mode, :increase_line_spacing, :decrease_line_spacing,
                         :toggle_page_numbering_mode, :sidebar_down, :sidebar_up, :sidebar_select, :sidebar_toggle_toc,
                         :handle_popup_action, :close_dictionary,
                         :dictionary_insert_char, :dictionary_backspace, :dictionary_confirm, :dictionary_cancel,
                         :dictionary_tab, :dictionary_swap_languages,
                         :dictionary_scroll_up, :dictionary_scroll_down,
                         :dictionary_toggle_fuzzy, :dictionary_cycle_result,
                         :dictionary_cycle_pair, :open_in_book_search, :close_in_book_search,
                         :in_book_search_insert_char, :in_book_search_backspace, :in_book_search_confirm,
                         :in_book_search_cancel, :in_book_search_up, :in_book_search_down,
                         :annotation_editor_insert_char, :annotation_editor_backspace, :annotation_editor_enter,
                         :annotation_editor_move_left, :annotation_editor_move_right, :annotation_editor_move_up,
                         :annotation_editor_move_down, :annotation_editor_cancel, :annotation_editor_save

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

          def initialize(epub_path, deps:, runtime_components_factory:)
            deps.validate!

            state = deps.state_facade
            workflow = deps.workflow_facade
            rendering = deps.rendering_facade
            lifecycle = deps.lifecycle_facade

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

            @navigation_service_ref = workflow.navigation_service
            @bookmark_service_ref = workflow.bookmark_service
            @popup_position_service_ref = workflow.popup_position_service
            @logger_ref = deps.logger
            @command_bus_ref = deps.command_bus
            @process_control_ref = deps.process_control
            @clock_ref = deps.clock
            @key_classifier = deps.key_classifier
            @selection_service_ref = workflow.selection_service
            @wrapping_service_ref = rendering.wrapping_service
            @rendered_content_reader = rendering.rendered_content_reader
            @annotation_service_ref = rendering.annotation_service
            @annotation_overlay_ui_session_ref = deps.annotation_overlay_ui_session
            @annotation_editor_launcher_ref = workflow.annotation_editor_launcher
            @render_registry_ref = rendering.render_registry
            @document_loader = rendering.document_loader
            @coordinate_service_ref = workflow.coordinate_service
            @document_path_resolver = workflow.document_path_resolver
            @reader_state_reader = state.reader_state_reader
            @state_writer = state.state_writer
            @config_reader = state.config_reader
            @reader_launch_state = deps.reader_launch_state
            @observer_registry = deps.observer_registry
            @pending_jump_handler_factory = workflow.pending_jump_handler_factory
            @reader_lifecycle_factory = lifecycle.reader_lifecycle_factory
            @lifecycle_facade = lifecycle
            @intent_handler = build_intent_handler(deps.intent_handler_factory)

            lifecycle_runner = build_reader_lifecycle
            @coordinators = Coordinators.new(lifecycle: lifecycle_runner,
                                             pagination_coordinator: nil,
                                             render_coordinator: nil)
            lifecycle_runner.ensure_background_worker

            @startup_loader = Reader::StartupLoader.new(
              path: epub_path,
              document_loader: @document_loader,
              reader_launch_state: @reader_launch_state,
              state_writer: @state_writer,
              document_matches_path: ->(existing, target_path) { document_matches_path?(existing, target_path) },
              logger: @logger_ref
            )

            target_path = canonical_reader_path(path)
            @context.doc = @startup_loader.validate_preloaded_document(deps.document, target_path)
            load_document unless doc
            @reader_launch_state.set_preloaded_document(doc) if @reader_launch_state && doc
            @state_writer.update_selections(book_path: epub_path)

            @controllers = ControllerRefs.new(
              ui_controller: nil,
              state_controller: nil,
              input_controller: nil
            )
            runtime_components = build_runtime_components!(runtime_components_factory)
            wire_runtime_components!(runtime_components)
          end

          def wire_runtime_components!(runtime_components)
            @controllers = ControllerRefs.new(
              ui_controller: runtime_components.ui_controller,
              state_controller: runtime_components.state_controller,
              input_controller: runtime_components.input_controller
            )
            @coordinators.pagination_coordinator = runtime_components.pagination_coordinator
            @coordinators.render_coordinator = runtime_components.render_coordinator

            @input_router = Reader::InputRouter.new(
              reader_state_reader: @reader_state_reader,
              input_controller: input_controller,
              ui_controller: ui_controller,
              key_classifier: @key_classifier
            )
            @render_metrics = Reader::RenderMetrics.new(
              instrumentation: instrumentation,
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
            self
          end
          private :wire_runtime_components!

          # Observer callback for state changes
          def state_changed(path, _old_value, new_value)
            case path
            when %i[reader sidebar_visible]
              begin
                pagination_coordinator.sync_sidebar_layout(sidebar_visible: new_value == true)
              rescue Shoko::Error
                raise
              end
              rebuild_root_layout
              force_redraw
            when %i[reader dictionary_visible], %i[reader dictionary_panel]
              rebuild_root_layout
            when %i[config theme]
              apply_theme_palette
            when %i[config view_mode], %i[config line_spacing], %i[config page_numbering_mode], %i[config kitty_images]
              begin
                pagination_coordinator.rebuild_after_config_change
              rescue Shoko::Error
                raise
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
          rescue Shoko::Error => e
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

          # Read-mode wrappers used by symbol-only input bindings.
          def read_scroll_down_or_sidebar(key = nil)
            return sidebar_down if sidebar_visible?

            execute_input_command(:scroll_down, key)
          end

          def read_scroll_up_or_sidebar(key = nil)
            return sidebar_up if sidebar_visible?

            execute_input_command(:scroll_up, key)
          end

          def read_confirm_or_sidebar(key = nil)
            return sidebar_select if sidebar_visible?

            execute_input_command(:next_page, key)
          end

          def read_space_or_sidebar_toggle(key = nil)
            return sidebar_toggle_toc if sidebar_visible? && sidebar_toc_tab?

            execute_input_command(:next_page, key)
          end

          def help_exit_to_read(_key = nil)
            switch_mode(:read)
          end

          def dictionary_insert_char_if_printable(key = nil)
            char = key.to_s
            return :pass unless Shoko::Shared::TextSanitizer.printable_char?(char)

            dictionary_insert_char(char)
          end

          def in_book_search_insert_char_if_printable(key = nil)
            char = key.to_s
            return :pass unless Shoko::Shared::TextSanitizer.printable_char?(char)

            in_book_search_insert_char(char)
          end

          def annotation_editor_insert_char_if_printable(key = nil)
            char = key.to_s
            return :pass unless Shoko::Shared::TextSanitizer.printable_char?(char)

            annotation_editor_insert_char(char)
          end

          private

          def build_intent_handler(intent_handler_factory)
            raise ArgumentError, 'intent_handler_factory is required' if intent_handler_factory.nil?

            handler = intent_handler_factory.call(self)
            return handler if handler.is_a?(Shoko::Core::Ports::Inbound::ReaderIntentHandler)

            raise ArgumentError,
                  "intent_handler_factory must build #{Shoko::Core::Ports::Inbound::ReaderIntentHandler}"
          end

          def build_runtime_components!(runtime_components_factory)
            raise ArgumentError, 'runtime_components_factory is required' if runtime_components_factory.nil?

            components = runtime_components_factory.call(self)
            return components if components.is_a?(RuntimeComponents)

            raise ArgumentError, 'runtime_components_factory must return ReaderController::RuntimeComponents'
          end

          def memo
            context.memo ||= {}
          end

          def monotonic_now
            @clock_ref.monotonic_now
          end

          def build_reader_lifecycle
            raise ArgumentError, 'reader_lifecycle_factory is required' if @reader_lifecycle_factory.nil?

            @reader_lifecycle_factory.call(
              self,
              terminal_session: @lifecycle_facade.terminal_session,
              background_worker: @lifecycle_facade.background_worker,
              background_worker_builder: @lifecycle_facade.background_worker_builder,
              async_executor: @lifecycle_facade.async_executor,
              instrumentation_service: @lifecycle_facade.instrumentation_service,
              logger: @logger_ref,
              pagination_cache_preloader: @lifecycle_facade.pagination_cache_preloader
            )
          end

          def build_pending_jump_handler
            raise ArgumentError, 'pending_jump_handler_factory is required' if @pending_jump_handler_factory.nil?

            @pending_jump_handler_factory.call(
              reader_state: @reader_state_reader,
              state_writer: @state_writer,
              annotation_editor_launcher: @annotation_editor_launcher_ref,
              rendered_content_reader: @rendered_content_reader,
              navigation_service: @navigation_service_ref,
              selection_service: @selection_service_ref,
              coordinate_service: @coordinate_service_ref
            )
          end

          def load_document
            loaded = @startup_loader.load_document(current_doc: doc, on_loaded: ->(fresh) { @context.doc = fresh })
            @context.doc = loaded
            loaded
          end

          def load_data
            @startup_loader.load_saved_state(state_controller: state_controller)
          end

          def apply_pending_jump_if_present
            @startup_loader.apply_pending_jump(jump_handler: jump_handler)
          end

          def jump_handler
            memo[:jump_handler] ||= build_pending_jump_handler
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

          def sidebar_visible?
            @reader_state_reader&.sidebar_visible? == true
          rescue Shoko::Error
            raise
          end

          def sidebar_toc_tab?
            @reader_state_reader&.sidebar_active_tab == :toc
          rescue Shoko::Error
            raise
          end

          def execute_input_command(command_symbol, key = nil)
            bus = command_bus
            unless bus
              command_logger&.error('command.contract_mismatch',
                                    command: command_symbol,
                                    reason: 'missing_command_bus',
                                    context: self.class.name)
              return :error
            end

            bus.execute_command(command_symbol, self, input_payload_for(key))
          rescue ArgumentError => e
            command_logger&.error('command.contract_mismatch',
                                  command: command_symbol,
                                  error_class: e.class.name,
                                  error: e.message,
                                  context: self.class.name)
            :error
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

          def canonical_reader_path(path)
            return path unless @document_path_resolver

            @document_path_resolver.canonical_reader_path(path)
          end

          def document_matches_path?(document, target_path)
            return false unless @document_path_resolver

            @document_path_resolver.document_matches_path?(document, target_path)
          end

          def input_payload_for(key)
            Shoko::Core::Ports::Inbound::InputCommandPayload.new(
              key: key,
              triggered_by: :input,
              args: [].freeze,
              metadata: {}.freeze,
              key_provided: !key.nil?
            )
          end

          public :current_editor_component
        end
      end
    end
  end
end
