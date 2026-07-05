# frozen_string_literal: true

require_relative '../dependencies/dependency_record_mixins'
require_relative 'state_controller'
require_relative 'input_controller'
require_relative 'intent_runtime_bridge'
require_relative 'translator_mouse_handler'
require_relative 'mouse_router'
require_relative 'workflow_render_observer'
require_relative 'input_mode_observer'
require 'shoko/shared/hash_normalizer'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Controller responsible for the menu orchestration loop.
          class Controller
            FallbackBounds = Data.define(:x, :y, :width, :height)

            RuntimeDependencies = Data.define(
              :observer_registry,
              :catalog,
              :terminal_service,
              :frame_coordinator,
              :render_pipeline,
              :menu_state_reader,
              :menu_session_mutator,
              :clock,
              :process_control
            ) do
              extend Shoko::Adapters::Input::Controllers::Dependencies::DependencyBuilder
              include Shoko::Adapters::Input::Controllers::Dependencies::Validation

              def self.required_fields
                %i[
                  observer_registry
                  catalog
                  terminal_service
                  frame_coordinator
                  render_pipeline
                  menu_state_reader
                  menu_session_mutator
                  clock
                ]
              end
            end

            BuilderDependencies = Data.define(
              :menu_ui_dependencies,
              :ui_component_factory,
              :key_classifier,
              :input_system_factory,
              :intent_handler_factory,
              :state_controller_factory
            ) do
              extend Shoko::Adapters::Input::Controllers::Dependencies::DependencyBuilder
              include Shoko::Adapters::Input::Controllers::Dependencies::Validation

              def self.required_fields
                members
              end
            end

            SupportDependencies = Data.define(
              :notification_service,
              :clipboard_service,
              :settings_service,
              :annotation_service,
              :logger,
              :file_probe,
              :path_ops
            ) do
              extend Shoko::Adapters::Input::Controllers::Dependencies::DependencyBuilder

              def validate!
                self
              end
            end

            attr_accessor :filtered_epubs
            attr_reader :observer_registry,
                        :main_menu_component,
                        :catalog,
                        :terminal_service,
                        :frame_coordinator,
                        :render_pipeline,
                        :state_controller,
                        :input_controller,
                        :menu_state_reader,
                        :menu_session_mutator,
                        :intent_handler,
                        :settings_service,
                        :annotation_service

            def initialize(runtime:, builder:, support:)
              runtime.validate!
              builder.validate!
              support.validate!

              assign_runtime_dependencies(runtime)
              assign_support_dependencies(support)
              build_menu_component(builder)
              @prepagination_toast = ui_component_factory.prepagination_toast(menu_state_reader: @menu_state_reader)
              @startup_notice = ui_component_factory.startup_notice(menu_state_reader: @menu_state_reader)
              @filtered_epubs = []
              build_input_graph(builder)
              register_workflow_render_observer
              register_input_mode_observer
            end

            # Shared runtime helper still used by workflow bridges.
            def switch_to_mode(mode)
              payload = { mode: mode, browse_selected: 0 }
              payload[:settings_selected] = 1 if mode == :settings
              payload[:library_details_open] = false if mode == :library
              @menu_session_mutator.update_menu(payload)
              # The reader disables terminal mouse tracking on its way out
              # (this is the path it hands control back through), so drop the
              # flag and let the next loop tick re-enable menu tracking.
              @menu_mouse_tracking = false
            end

            # Thin convenience API retained for non-input collaborators and focused specs.
            def library_toggle_details
              @intent_handler.handle_menu_intent(:toggle_library_details)
            end

            def switch_to_search
              @intent_handler.handle_menu_intent(:switch_to_search_mode)
            end

            # The run loop is the process's last isolation boundary: any error
            # escaping it — domain or plain bug — must end in a restored
            # terminal and a clean exit message, never a raw backtrace.
            def run
              bootstrap_catalog
              main_loop
            rescue Interrupt
              cleanup_and_exit(0, "\nGoodbye!")
            rescue Shoko::FatalExternalInputError => e
              log_fatal_external_input(e)
              cleanup_and_exit(2, "Fatal external input error: #{e.message}", e)
            # resilient-boundary
            rescue StandardError => e
              handle_fatal_menu_error(e)
            ensure
              ensure_terminal_cleanup
              @catalog.cleanup
            end

            def handle_fatal_menu_error(error)
              cleanup_and_exit(1, "Error: #{error.message} (#{error.class})", error)
            end

            def cleanup_and_exit(code, message, error = nil)
              cleanup_terminal

              emit_exit_message(message, error)
              log_exit(message, error)
              @process_control&.terminate(code)
            end

            # The terminal is restored at this point, so the message can land on
            # the normal screen — exiting silently after an error (visible only
            # in an off-by-default log) is how crashes go unreported.
            def emit_exit_message(message, error)
              return if message.to_s.empty?

              $stdout.puts(message)
              $stdout.puts('Run with --log PATH --log-level debug for details.') if error
            # resilient-boundary
            rescue StandardError => e
              record_exit_message_error(e)
            end

            def record_exit_message_error(error)
              @logger_ref&.debug('menu.exit_message_failed', error: error.class.name, message: error.message)
            end

            # Relays carrying async workflow results (downloads, translation,
            # RSS). The loop drains them so network work done on worker
            # threads lands in menu state on this thread.
            def attach_workflow_relays(relays)
              @workflow_relays = Array(relays)
            end

            def main_loop
              draw_screen
              loop do
                process_scan_results_if_available
                handle_user_input
                process_workflow_events
                consume_pending_resize
                draw_screen
              end
            end

            def process_workflow_events
              Array(@workflow_relays).each(&:drain!)
            end

            def workflow_network_pending?
              Array(@workflow_relays).any?(&:busy?)
            end

            # Refreshes the cached terminal size after SIGWINCH so the redraw
            # below lays the menu out against the new dimensions immediately.
            def consume_pending_resize
              @terminal_service.consume_resize_event? if @terminal_service.respond_to?(:consume_resize_event?)
            end

            def handle_user_input
              sync_menu_mouse_tracking
              keys = read_input_keys(timeout: input_poll_interval)
              remaining = consume_menu_mouse_input(keys)
              input_controller.handle_keys(remaining) unless remaining.empty?
            end

            def read_input_keys(timeout: nil)
              @terminal_service.read_keys_blocking(limit: 10, timeout: timeout)
            end

            def process_scan_results_if_available
              return unless (epubs = @catalog.process_results)

              @filtered_epubs = epubs
              @main_menu_component.browse_screen.filtered_epubs = epubs
              @main_menu_component.library_screen.invalidate_cache!
            end

            def draw_screen
              notification_service&.tick
              metadata_refresh_pending = catalog_metadata_refresh_pending?
              @frame_coordinator.with_frame do |surface, bounds, _w, _h|
                @render_pipeline.render_component(surface, bounds, @main_menu_component)
                @prepagination_toast.render(surface, bounds)
                @startup_notice.render(surface, bounds)
              end
              @catalog.consume_metadata_refresh! if metadata_refresh_pending &&
                                                    @catalog.respond_to?(:consume_metadata_refresh!)
            end

            def annotation_editor_active?
              @menu_state_reader.mode == :annotation_editor
            rescue Shoko::Error => e
              raise if e.is_a?(Shoko::FatalExternalInputError)

              @logger_ref&.debug('menu.annotation_editor_active_check_failed',
                                 error: e.class.name,
                                 message: e.message)
              false
            end

            # The translator input shows a blinking caret too, so it needs the same idle redraw
            # cadence as the note editor — otherwise the loop blocks on input and the caret freezes.
            def translator_input_active?
              @menu_state_reader.mode == :translator &&
                (@menu_state_reader.translator_focus || :input).to_sym == :input
            rescue Shoko::Error => e
              raise if e.is_a?(Shoko::FatalExternalInputError)

              @logger_ref&.debug('menu.translator_input_active_check_failed',
                                 error: e.class.name,
                                 message: e.message)
              false
            end

            def blink_poll_interval
              0.1
            end

            def input_poll_interval
              return blink_poll_interval if annotation_editor_active?
              return blink_poll_interval if translator_input_active?
              return blink_poll_interval if catalog_scan_pending?
              return blink_poll_interval if catalog_metadata_refresh_needed?
              return blink_poll_interval if prepagination_active?
              return blink_poll_interval if workflow_network_pending?

              nil
            end

            # Keep polling (and thus redrawing) while the library pre-pagination
            # toast is up so its spinner animates instead of freezing on the menu's
            # otherwise blocking idle read.
            def prepagination_active?
              @menu_state_reader.respond_to?(:prepaginate_active) && @menu_state_reader.prepaginate_active == true
            end

            private

            attr_reader :notification_service

            def logger
              @logger_ref
            end

            def ui_component_factory
              @ui_component_factory_ref
            end

            def assign_runtime_dependencies(runtime)
              @observer_registry = runtime.observer_registry
              @catalog = runtime.catalog
              @terminal_service = runtime.terminal_service
              @frame_coordinator = runtime.frame_coordinator
              @render_pipeline = runtime.render_pipeline
              @menu_state_reader = runtime.menu_state_reader
              @menu_session_mutator = runtime.menu_session_mutator
              @clock = runtime.clock
              @process_control = runtime.process_control
            end

            def assign_support_dependencies(support)
              @notification_service = support.notification_service
              @clipboard_service = support.clipboard_service
              @settings_service = support.settings_service
              @annotation_service = support.annotation_service
              @logger_ref = support.logger
              @file_probe = support.file_probe
              @path_ops = support.path_ops
            end

            def build_menu_component(builder)
              @ui_component_factory_ref = builder.ui_component_factory
              @main_menu_component = ui_component_factory.main_menu_component(
                controller: self,
                menu_ui_dependencies: builder.menu_ui_dependencies
              )
            end

            def build_input_graph(builder)
              @state_controller = builder.state_controller_factory.call(self)
              @intent_handler = builder.intent_handler_factory.call(self)
              @mouse_handler = builder.input_system_factory.create_mouse_handler
              @input_controller = InputController.new(
                self,
                key_classifier: builder.key_classifier,
                input_system_factory: builder.input_system_factory,
                intent_handler: @intent_handler
              )
              @translator_mouse_handler = build_translator_mouse_handler
              @menu_mouse_router = build_menu_mouse_router
              @dispatcher = @input_controller.dispatcher
            end

            def build_translator_mouse_handler
              TranslatorMouseHandler.new(
                menu_state_reader: @menu_state_reader,
                menu_session_mutator: @menu_session_mutator,
                input_controller: @input_controller,
                translator_screen: @main_menu_component.translator_screen,
                clipboard_service: @clipboard_service,
                notification_service: @notification_service
              )
            end

            def build_menu_mouse_router
              MouseRouter.new(
                hit_registry: @main_menu_component.hit_registry,
                menu_state_reader: @menu_state_reader,
                menu_session_mutator: @menu_session_mutator,
                intent_handler: @intent_handler,
                main_menu_component: @main_menu_component
              )
            end

            def register_workflow_render_observer
              observer = WorkflowRenderObserver.new(menu: self, clock: @clock, logger: logger)
              @observer_registry.add_observer(observer, *observer.observed_paths)
            end

            def register_input_mode_observer
              observer = InputModeObserver.new(input_controller: @input_controller, logger: logger)
              @observer_registry.add_observer(observer, *observer.observed_paths)
            end

            def cleanup_terminal
              terminal = terminal_service
              return unless terminal

              cleanup_error = nil
              begin
                disable_menu_mouse_tracking
                terminal.cleanup
              # resilient-boundary
              rescue StandardError => e
                cleanup_error = e
                record_terminal_cleanup_error(e)
              ensure
                force_cleanup_if_needed(terminal, cleanup_error)
              end
            end

            def record_terminal_cleanup_error(error)
              @logger_ref&.error('Menu terminal cleanup failed',
                                 error_class: error.class.name, error: error.message)
            end

            def catalog_metadata_refresh_needed?
              (@catalog.respond_to?(:metadata_work_pending?) && @catalog.metadata_work_pending?) ||
                catalog_metadata_refresh_pending?
            end

            def catalog_metadata_refresh_pending?
              @catalog.respond_to?(:metadata_refresh_pending?) && @catalog.metadata_refresh_pending?
            end

            def catalog_scan_pending?
              @catalog.respond_to?(:scan_status) && @catalog.scan_status == :scanning
            end

            def force_cleanup_if_needed(terminal, cleanup_error)
              remaining_depth = terminal.session_depth || 0
              needs_force = cleanup_error || remaining_depth.positive?
              return unless needs_force

              terminal.force_cleanup
            # resilient-boundary
            rescue StandardError => e
              record_force_cleanup_error(e)
            end

            def record_force_cleanup_error(error)
              @logger_ref&.error('Menu terminal force cleanup failed',
                                 error_class: error.class.name, error: error.message)
            end

            def log_exit(message, error)
              @logger_ref&.info('Exiting menu', message: message, status: error ? 'error' : 'ok')
              return unless error

              @logger_ref&.error('Menu exit error', error: error.message, backtrace: Array(error.backtrace))
            end

            def log_fatal_external_input(error)
              @logger_ref&.error(fatal_event_id_for(error), error: error.class.name, message: error.message)
            end

            def bootstrap_catalog
              @terminal_service.setup
              @catalog.load_cached
              epubs = @catalog.entries || []
              @filtered_epubs = epubs
              @main_menu_component.browse_screen.filtered_epubs = epubs
              @catalog.start_scan(force: true, preserve_entries: true)
            end

            def ensure_terminal_cleanup
              @terminal_service.force_cleanup
            # resilient-boundary
            rescue StandardError => e
              record_ensure_cleanup_error(e)
            end

            def record_ensure_cleanup_error(error)
              @logger_ref&.debug('menu.run.ensure_terminal_cleanup_failed',
                                 error: error.class.name, message: error.message)
            end

            def fatal_event_id_for(error)
              case error
              when Shoko::MalformedBookInputError
                'fatal.external_input.book'
              when Shoko::MalformedMetadataInputError
                'fatal.external_input.metadata'
              when Shoko::MalformedDictionaryInputError
                'fatal.external_input.dictionary'
              else
                'fatal.external_input.unknown'
              end
            end

            # The whole menu is mouseable: tracking stays on for the entire
            # menu session and is released with the terminal on cleanup (the
            # reader manages its own tracking while a book is open).
            def sync_menu_mouse_tracking
              enable_menu_mouse_tracking unless @menu_mouse_tracking
            end

            def enable_menu_mouse_tracking
              @terminal_service.enable_mouse
              @menu_mouse_tracking = true
            end

            def disable_menu_mouse_tracking
              return unless @menu_mouse_tracking

              @terminal_service.disable_mouse
              @menu_mouse_tracking = false
            rescue Shoko::Error
              @menu_mouse_tracking = false
            end

            def consume_menu_mouse_input(keys)
              Array(keys).each_with_object([]) do |key, remaining|
                menu_mouse_sequence?(key) ? handle_menu_mouse_sequence(key) : remaining << key
              end
            end

            def menu_mouse_sequence?(token)
              @mouse_handler&.mouse_sequence?(token)
            end

            # The translator's own handler (drag selection, clipboard menu,
            # dropdown clicks) gets first refusal in translator mode; anything
            # it declines — rail clicks, wheel turns — falls through to the
            # menu-wide router, which consumes every remaining mouse token so
            # none leak into key handling.
            def handle_menu_mouse_sequence(token)
              event = @mouse_handler.parse_mouse_event(token)
              return unless event
              return if translator_mouse_mode? && handle_translator_mouse_event(event)

              @menu_mouse_router&.handle(event)
            end

            def handle_translator_mouse_event(event)
              bounds = translator_bounds
              local = event.merge(x: event[:x] - (bounds.x - 1), y: event[:y] - (bounds.y - 1))
              return true if @translator_mouse_handler&.handle(local, bounds: bounds)
              return false unless translator_click_release?(local)

              action = translator_screen.hit_test(local[:x] + 1, local[:y] + 1, bounds)
              return false unless action

              apply_translator_mouse_action(action)
              true
            end

            def translator_click_release?(event)
              event[:released] && event[:button].to_i.zero?
            end

            # The rect the translator rendered into on the last frame; falls
            # back to the full terminal before the first paint.
            def translator_bounds
              canvas = @main_menu_component&.canvas_bounds
              return canvas if canvas

              height, width = @terminal_service.size
              FallbackBounds.new(x: 1, y: 1, width: width, height: height)
            end

            def apply_translator_mouse_action(action)
              return unless action

              case action[:type]
              when :focus then focus_translator_input
              when :toggle_dropdown then toggle_translator_dropdown(action[:kind])
              when :select_language then click_translator_language(action)
              end
            end

            # The menu's click grammar: the first click moves the highlight to
            # the language under the pointer; a click on the already-highlighted
            # candidate applies it (and closes the picker).
            def click_translator_language(action)
              current = (@menu_state_reader.translator_dropdown_selected || 0).to_i
              return select_translator_language(action) if current == action[:index].to_i

              @menu_session_mutator.update_menu(translator_dropdown_selected: action[:index])
            end

            def focus_translator_input
              @menu_session_mutator.update_menu(
                mode: :translator,
                translator_focus: :input,
                translator_selection: nil,
                translator_context_menu: nil
              )
            end

            def toggle_translator_dropdown(kind)
              dropdown_mode = kind == :source ? :translator_source_dropdown : :translator_target_dropdown
              return close_translator_dropdown(kind) if @menu_state_reader.mode == dropdown_mode

              open_translator_dropdown(kind, dropdown_mode)
            end

            def close_translator_dropdown(kind)
              @menu_session_mutator.update_menu(
                mode: :translator,
                translator_focus: kind,
                translator_selection: nil,
                translator_context_menu: nil
              )
            end

            def open_translator_dropdown(kind, dropdown_mode)
              @menu_session_mutator.update_menu(
                mode: dropdown_mode,
                translator_focus: kind,
                translator_dropdown_selected: translator_language_index(kind),
                translator_selection: nil,
                translator_context_menu: nil
              )
            end

            def select_translator_language(action)
              @menu_session_mutator.update_menu(translator_language_payload(action))
              translate_from_current_translator_state
            end

            def translator_language_payload(action)
              field = action[:kind] == :source ? :translator_source_lang : :translator_target_lang
              {
                mode: :translator,
                translator_focus: action[:kind],
                translator_dropdown_selected: action[:index],
                translator_selection: nil,
                translator_context_menu: nil,
                field => action[:code],
              }
            end

            def translate_from_current_translator_state
              text = @menu_state_reader.translator_input_text.to_s
              return if text.strip.empty?

              @state_controller.translate_text(
                text: text,
                source_lang: @menu_state_reader.translator_source_lang,
                target_lang: @menu_state_reader.translator_target_lang
              )
            end

            def translator_language_index(kind)
              code = selected_translator_language_code(kind)
              translator_language_options(kind).index { |item| item[:code] == code.to_s } || 0
            end

            def selected_translator_language_code(kind)
              return @menu_state_reader.translator_source_lang if kind == :source

              @menu_state_reader.translator_target_lang
            end

            def translator_language_options(kind)
              languages = Array(@menu_state_reader.translator_languages).map { |item| normalize_language(item) }
              kind == :source ? [{ code: 'auto', name: 'Auto Detect' }, *languages] : languages
            end

            def normalize_language(item)
              normalized = Shoko::Shared::HashNormalizer.symbolize_keys(item) || {}
              {
                code: normalized[:code].to_s,
                name: normalized[:name].to_s,
              }
            end

            def translator_mouse_mode?
              %i[translator translator_source_dropdown translator_target_dropdown].include?(@menu_state_reader.mode)
            end

            def translator_screen
              @main_menu_component.translator_screen
            end
          end
        end
      end
    end
  end
end
