# frozen_string_literal: true

require_relative '../dependencies/dependency_record_mixins'
require_relative 'state_controller'
require_relative 'input_controller'
require_relative 'intent_runtime_bridge'
require_relative 'translator_mouse_handler'
require_relative 'workflow_render_observer'
require_relative 'input_mode_observer'
require_relative '../../../../shared/hash_normalizer'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Controller responsible for the menu orchestration loop.
          class Controller
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
            end

            # Thin convenience API retained for non-input collaborators and focused specs.
            def library_toggle_details
              @intent_handler.handle_menu_intent(:toggle_library_details)
            end

            def switch_to_search
              @intent_handler.handle_menu_intent(:switch_to_search_mode)
            end


            def run
              bootstrap_catalog
              main_loop
            rescue Interrupt
              cleanup_and_exit(0, "\nGoodbye!")
            rescue Shoko::FatalExternalInputError => e
              log_fatal_external_input(e)
              cleanup_and_exit(2, "Fatal external input error: #{e.message}", e)
            # resilient-boundary
            rescue Shoko::Error => e
              cleanup_and_exit(1, "Error: #{e.message}", e)
            ensure
              ensure_terminal_cleanup
              @catalog.cleanup
            end

            def cleanup_and_exit(code, message, error = nil)
              cleanup_terminal

              log_exit(message, error)
              @process_control&.terminate(code)
            end

            def main_loop
              draw_screen
              loop do
                process_scan_results_if_available
                handle_user_input
                draw_screen
              end
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

            def blink_poll_interval
              0.1
            end

            def input_poll_interval
              return blink_poll_interval if annotation_editor_active?
              return blink_poll_interval if catalog_scan_pending?
              return blink_poll_interval if catalog_metadata_refresh_needed?

              nil
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
              rescue Shoko::Error => e
                cleanup_error = e
                @logger_ref&.error('Menu terminal cleanup failed', error: e.message)
              ensure
                force_cleanup_if_needed(terminal, cleanup_error)
              end
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
            rescue Shoko::Error => e
              @logger_ref&.error('Menu terminal force cleanup failed', error: e.message)
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
            rescue Shoko::Error => e
              @logger_ref&.debug('menu.run.ensure_terminal_cleanup_failed', error: e.class.name, message: e.message)
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


            def sync_menu_mouse_tracking
              return enable_menu_mouse_tracking if translator_mouse_mode? && !@menu_mouse_tracking
              return disable_menu_mouse_tracking if !translator_mouse_mode? && @menu_mouse_tracking

              nil
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
              return Array(keys) unless translator_mouse_mode?

              Array(keys).each_with_object([]) do |key, remaining|
                translator_mouse_sequence?(key) ? handle_translator_mouse_sequence(key) : remaining << key
              end
            end

            def translator_mouse_sequence?(token)
              @mouse_handler&.mouse_sequence?(token)
            end

            def handle_translator_mouse_sequence(token)
              event = @mouse_handler.parse_mouse_event(token)
              return unless event
              return if @translator_mouse_handler&.handle(event, bounds: translator_bounds)
              return unless translator_click_release?(event)

              action = translator_screen.hit_test(event[:x] + 1, event[:y] + 1, translator_bounds)
              apply_translator_mouse_action(action)
            end

            def translator_click_release?(event)
              event[:released] && event[:button].to_i.zero?
            end

            def translator_bounds
              height, width = @terminal_service.size
              Struct.new(:width, :height).new(width, height)
            end

            def apply_translator_mouse_action(action)
              return unless action

              case action[:type]
              when :focus then focus_translator_input
              when :toggle_dropdown then toggle_translator_dropdown(action[:kind])
              when :select_language then select_translator_language(action)
              end
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
