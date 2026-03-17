# frozen_string_literal: true

require 'forwardable'
require_relative '../../../shared/errors'
require_relative 'reader/intent_runtime_bridge'
require_relative 'reader/runtime_types'
require_relative 'reader/runtime_setup'
require_relative 'reader/state_observer'

require_relative 'reader/input_router'
require_relative 'reader/event_loop'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Coordinator class for the reading experience.
        class ReaderController
          extend Forwardable

          attr_reader :context, :services, :controllers, :coordinators, :observer_registry

          def_delegators :context, :path, :doc, :metrics_start_time
          def_delegators :services, :page_calculator, :terminal_service, :clipboard_service, :instrumentation
          def_delegators :controllers, :ui_controller, :state_controller, :input_controller
          def_delegators :coordinators, :lifecycle, :pagination_coordinator, :render_coordinator

          # Service accessors for commands and collaborators
          attr_reader :navigation_service_ref, :bookmark_service_ref, :popup_position_service_ref,
                      :logger_ref, :process_control_ref, :intent_handler
          attr_reader :clock_ref
          attr_reader :selection_service_ref, :coordinate_service_ref, :rendered_content_reader
          attr_reader :reader_state_reader, :reader_session_mutator, :config_reader

          alias navigation_service navigation_service_ref
          alias bookmark_service bookmark_service_ref
          alias popup_position_service popup_position_service_ref
          alias logger logger_ref
          alias process_control process_control_ref
          alias clock clock_ref
          alias selection_service selection_service_ref
          alias coordinate_service coordinate_service_ref

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
                         :annotation_editor_move_down, :annotation_editor_cancel, :annotation_editor_save,
                         :annotation_editor_spellcheck

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

          def initialize(epub_path, core:, state:, services:, runtime_boot:, runtime_startup:, runtime_components_factory:)
            [core, state, services, runtime_boot, runtime_startup].each(&:validate!)

            @context = Reader::RuntimeTypes::Context.new(
              path: epub_path,
              doc: nil,
              metrics_start_time: nil
            )

            @services = Reader::RuntimeTypes::Services.new(
              page_calculator: core.page_calculator,
              terminal_service: core.terminal_service,
              clipboard_service: core.clipboard_service,
              instrumentation: core.instrumentation
            )

            @navigation_service_ref = services.navigation_service
            @bookmark_service_ref = services.bookmark_service
            @popup_position_service_ref = services.popup_position_service
            @logger_ref = core.logger
            @process_control_ref = core.process_control
            @clock_ref = core.clock
            @selection_service_ref = state.selection_service
            @wrapping_service_ref = state.wrapping_service
            @rendered_content_reader = services.rendered_content_reader
            @annotation_service_ref = services.annotation_service
            @render_registry_ref = services.render_registry
            @coordinate_service_ref = services.coordinate_service
            @reader_state_reader = state.reader_state_reader
            @reader_session_mutator = state.reader_session_mutator
            @ui_state_reader = state.ui_state_reader
            @config_reader = state.config_reader
            @observer_registry = state.observer_registry
            @state_observer = Reader::StateObserver.new(controller: self)

            apply_runtime_setup!(
              Reader::RuntimeSetup.new(
                controller: self,
                epub_path: epub_path,
                boot: runtime_boot,
                startup: runtime_startup,
                runtime_components_factory: runtime_components_factory
              ).call
            )
          end

          def apply_runtime_setup!(setup)
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
            apply_theme_palette
            @startup_loader.apply_pending_jump(jump_handler: @pending_jump_handler)
            build_component_layout
            input_controller.setup_input_dispatcher(@intent_handler)
            @reader_session_mutator.update_reader(running: true)
            self
          end
          private :apply_runtime_setup!

          # Observer callback for state changes
          def state_changed(path, _old_value, new_value)
            @state_observer.handle(path, new_value)
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
            Reader::EventLoop.new(self, @reader_state_reader, metrics_start_time, instrumentation,
                                  clock: @clock_ref).run
          end

          def mark_metrics_start!
            context.metrics_start_time = monotonic_now
          end

          private

          def monotonic_now
            @clock_ref.monotonic_now
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
          end

          def sidebar_toc_tab?
            @reader_state_reader&.sidebar_active_tab == :toc
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

          # Ensure both UI state and any local selection handlers are cleared
          def cleanup_popup_state
            ui_controller.cleanup_popup_state
            clear_selection!
          end
        end
      end
    end
  end
end
