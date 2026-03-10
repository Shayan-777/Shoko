# frozen_string_literal: true

require_relative 'state_controller'
require_relative 'input_controller'
require_relative 'intent_runtime_bridge'
require_relative 'actions/lifecycle_actions'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Controller responsible for the menu orchestration loop.
          class Controller
            include Actions::Lifecycle

            module DependencyBuilder
              def build(**kwargs)
                new(**kwargs.slice(*members))
              end
            end

            module Validation
              def validate!
                missing = Array(self.class.required_fields).select { |field| public_send(field).nil? }
                return self if missing.empty?

                raise ArgumentError, "Missing required #{self.class.name.split('::').last}: #{missing.join(', ')}"
              end
            end

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
              extend DependencyBuilder
              include Validation

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
              extend DependencyBuilder
              include Validation

              def self.required_fields
                members
              end
            end

            SupportDependencies = Data.define(
              :notification_service,
              :settings_service,
              :annotation_service,
              :logger,
              :file_probe,
              :path_ops
            ) do
              extend DependencyBuilder

              def validate!
                self
              end
            end

            attr_accessor :filtered_epubs
            attr_reader :observer_registry, :main_menu_component, :catalog,
                        :terminal_service, :frame_coordinator, :render_pipeline,
                        :state_controller, :input_controller, :menu_state_reader, :menu_session_mutator,
                        :intent_handler, :settings_service, :annotation_service

            def initialize(runtime:, builder:, support:)
              runtime.validate!
              builder.validate!
              support.validate!

              @observer_registry = runtime.observer_registry
              @catalog = runtime.catalog
              @terminal_service = runtime.terminal_service
              @frame_coordinator = runtime.frame_coordinator
              @render_pipeline = runtime.render_pipeline
              @ui_component_factory_ref = builder.ui_component_factory
              @main_menu_component = ui_component_factory.main_menu_component(
                controller: self,
                menu_ui_dependencies: builder.menu_ui_dependencies
              )
              @filtered_epubs = []
              @notification_service = support.notification_service
              @settings_service = support.settings_service
              @annotation_service = support.annotation_service
              @logger_ref = support.logger
              @menu_state_reader = runtime.menu_state_reader
              @menu_session_mutator = runtime.menu_session_mutator
              @file_probe = support.file_probe
              @path_ops = support.path_ops
              @clock = runtime.clock
              @process_control = runtime.process_control

              @state_controller = builder.state_controller_factory.call(self)
              @intent_handler = builder.intent_handler_factory.call(self)
              @input_controller = InputController.new(
                self,
                key_classifier: builder.key_classifier,
                input_system_factory: builder.input_system_factory,
                intent_handler: @intent_handler
              )
              @dispatcher = @input_controller.dispatcher
            end

            # Public workflow API for reader-launch book selection.
            def selected_book_for_reader_launch
              index = (@menu_state_reader.browse_selected || 0).to_i
              main_menu_component.browse_screen.book_at(index)
            end

            # Public workflow API for annotation actions.
            def selected_annotation_for_workflow
              screen = @main_menu_component.annotations_screen
              {
                annotation: screen.current_annotation,
                book_path: screen.current_book_path,
              }
            end

            # Public workflow API for annotation view refreshes.
            def refresh_annotations_view_for_workflow
              @main_menu_component.annotations_screen.refresh_data
            end

            # Shared runtime helper still used by workflow bridges.
            def switch_to_mode(mode)
              payload = { mode: mode, browse_selected: 0 }
              payload[:settings_selected] = 1 if mode == :settings
              payload[:library_details_open] = false if mode == :library
              @menu_session_mutator.update_menu(payload)
              input_controller.activate(mode)
            end

            def cleanup_and_exit(code, message, error = nil)
              super
            end

            # Thin convenience API retained for non-input collaborators and focused specs.
            def library_toggle_details
              @intent_handler.handle_menu_intent(:toggle_library_details)
            end

            def switch_to_search
              @intent_handler.handle_menu_intent(:switch_to_search_mode)
            end

            private

            attr_reader :notification_service

            def logger
              @logger_ref
            end

            def ui_component_factory
              @ui_component_factory_ref
            end

            def resolve_library_path(item)
              primary = item.open_path
              return primary if state_controller.valid_cache_path?(primary)

              nil
            end
          end
        end
      end
    end
  end
end
