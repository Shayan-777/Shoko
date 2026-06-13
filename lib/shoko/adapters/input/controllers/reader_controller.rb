# frozen_string_literal: true

require 'forwardable'
require 'shoko/shared/errors'
require_relative 'reader/controller_interface'
require_relative 'reader/intent_runtime_bridge'
require_relative 'reader/runtime_types'
require_relative 'reader/runtime_setup'
require_relative 'reader/state_observer'
require_relative 'reader/progress_autosave'

require_relative 'reader/input_router'
require_relative 'reader/event_loop'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Coordinator class for the reading experience.
        class ReaderController
          extend Forwardable

          Reader::ControllerInterface.apply_to(self)

          attr_reader :context,
                      :services,
                      :controllers,
                      :coordinators,
                      :observer_registry,
                      :clock_ref,
                      :selection_service_ref,
                      :coordinate_service_ref,
                      :rendered_content_reader,
                      :reader_state_reader,
                      :reader_session_mutator,
                      :config_reader,
                      :references,
                      :navigation_service_ref,
                      :bookmark_service_ref,
                      :annotation_service_ref,
                      :popup_position_service_ref,
                      :logger_ref,
                      :process_control_ref,
                      :intent_handler

          def initialize(
            epub_path,
            core:,
            state:,
            services:,
            runtime_boot:,
            runtime_startup:,
            runtime_components_factory:
          )
            [core, state, services, runtime_boot, runtime_startup].each(&:validate!)

            @context = Reader::RuntimeTypes.context_for(epub_path)
            @render_pending = false
            @services = Reader::RuntimeTypes.services_for(core)
            @references = Reader::RuntimeTypes.references_for(core: core, state: state, services: services)
            assign_service_reference_aliases(@references)
            assign_state_reference_aliases(@references)
            @observer_registry = state.observer_registry
            @state_observer = Reader::StateObserver.new(
              controller: self,
              progress_autosave: Reader::ProgressAutosave.new(controller: self, clock: @clock_ref)
            )
            apply_runtime_setup!(
              build_runtime_setup(epub_path, runtime_boot, runtime_startup, runtime_components_factory)
            )
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
            @logger_ref&.debug('reader_controller.cleanup_observers_failed', error: e.class.name, message: e.message)
          end

          def main_loop
            Reader::EventLoop.new(
              self,
              @reader_state_reader,
              metrics_start_time,
              instrumentation,
              clock: @clock_ref
            ).run
          end

          def mark_metrics_start! = context.metrics_start_time = monotonic_now

          # True once per terminal-resize burst (SIGWINCH); the event loop
          # redraws so the resize applies while the reader is otherwise idle.
          def consume_pending_resize?
            terminal_service.respond_to?(:consume_resize_event?) && terminal_service.consume_resize_event?
          end

          # Marks a render as pending and wakes the event loop's blocked input
          # read. Safe from worker threads: the flag is only consumed (and the
          # frame drawn) on the UI thread, mirroring the resize path.
          def request_render
            @render_pending = true
            terminal_service.wake_input if terminal_service.respond_to?(:wake_input)
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

          private

          def assign_service_reference_aliases(references)
            @navigation_service_ref = references.navigation_service
            @bookmark_service_ref = references.bookmark_service
            @popup_position_service_ref = references.popup_position_service
            @logger_ref = references.logger
            @process_control_ref = references.process_control
            @clock_ref = references.clock
            @selection_service_ref = references.selection_service
            @wrapping_service_ref = references.wrapping_service
            @rendered_content_reader = references.rendered_content_reader
            @annotation_service_ref = references.annotation_service
            @render_registry_ref = references.render_registry
            @coordinate_service_ref = references.coordinate_service
          end

          def assign_state_reference_aliases(references)
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

          def monotonic_now = @clock_ref.monotonic_now

          def read_input_keys(timeout: nil)
            terminal_service.read_keys_blocking(limit: 10, timeout: timeout)
          end

          # Delegate wrapping through the DI-backed wrapping service when available.
          def wrap_lines(lines, width)
            if @wrapping_service_ref
              chapter_index = @reader_state_reader&.current_chapter || 0
              return @wrapping_service_ref.wrap_lines(lines, chapter_index, width)
            end

            lines
          end

          # Hook for subclasses to clear any active selection or popup state.
          def clear_selection!
            # no-op in base controller
          end

          # Clear popup UI state and any local selection handlers.
          def cleanup_popup_state
            ui_controller.cleanup_popup_state
            clear_selection!
          end
        end
      end
    end
  end
end
