# frozen_string_literal: true

require_relative '../../../../adapters/input/controllers/reader/intent_runtime_bridge'
require_relative '../../../../application/use_cases/reader_intent_handler'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderBuilder
          # Builds the staged reader controller dependency groups.
          module ControllerDependencyFactory
            module_function

            def build(prepared)
              DependencySet::ControllerDependencies.new(
                core: build_core_dependencies(prepared),
                state: build_state_dependencies(prepared),
                services: build_service_dependencies(prepared),
                runtime_boot: build_runtime_boot_dependencies(prepared),
                runtime_startup: build_runtime_startup_dependencies(prepared),
                mouse_support: build_mouse_support_dependencies(prepared)
              )
            end

            def build_core_dependencies(prepared)
              deps::ReaderControllerCoreDependencies.new(
                page_calculator: prepared.page_calculator,
                terminal_service: prepared.terminal_service,
                clipboard_service: prepared.clipboard_service,
                instrumentation: prepared.instrumentation,
                logger: prepared.logger,
                clock: prepared.clock,
                process_control: prepared.process_control
              ).validate!
            end
            private_class_method :build_core_dependencies

            def build_state_dependencies(prepared)
              deps::ReaderControllerStateDependencies.new(
                observer_registry: prepared.observer_registry,
                config_reader: prepared.app_config_store,
                reader_state_reader: prepared.reader_state_reader,
                reader_session_mutator: prepared.reader_session_mutator,
                ui_state_reader: prepared.reader_runtime_context,
                selection_service: prepared.selection_service,
                wrapping_service: prepared.wrapping_service
              ).validate!
            end
            private_class_method :build_state_dependencies

            def build_service_dependencies(prepared)
              deps::ReaderControllerServiceDependencies.new(
                navigation_service: prepared.navigation_service,
                bookmark_service: prepared.bookmark_service,
                popup_position_service: prepared.popup_position_service,
                rendered_content_reader: prepared.rendered_content_reader,
                annotation_service: prepared.annotation_service,
                render_registry: prepared.render_registry,
                coordinate_service: prepared.coordinate_service
              ).validate!
            end
            private_class_method :build_service_dependencies

            def build_runtime_boot_dependencies(prepared)
              deps::ReaderRuntimeBootDependencies.new(
                reader_lifecycle_factory: prepared.reader_lifecycle_factory,
                terminal_session: prepared.terminal_session,
                background_worker: prepared.worker,
                background_worker_builder: prepared.background_worker_builder,
                async_executor: prepared.async_executor,
                instrumentation_service: prepared.instrumentation_service,
                warmup_services: build_warmup_services(prepared)
              ).validate!
            end
            private_class_method :build_runtime_boot_dependencies

            def build_warmup_services(prepared)
              deps::ReaderWarmupServices.new(
                pagination_cache_preloader: prepared.pagination_cache_preloader,
                image_cache_warmup: prepared.image_cache_warmup,
                kitty_image_renderer: prepared.kitty_image_renderer
              )
            end
            private_class_method :build_warmup_services

            def build_runtime_startup_dependencies(prepared)
              deps::ReaderRuntimeStartupDependencies.new(
                intent_handler_factory: reader_intent_handler_factory(
                  reader_session_store: prepared.reader_session_store
                ),
                pending_jump_handler_factory: prepared.pending_jump_handler_factory,
                document_loader: prepared.document_loader,
                reader_document_locator: prepared.reader_document_locator,
                reader_launch_state: prepared.reader_launch_state,
                document: prepared.document,
                annotation_editor_launcher: prepared.annotation_editor_launcher,
                key_classifier: prepared.key_classifier
              ).validate!
            end
            private_class_method :build_runtime_startup_dependencies

            def build_mouse_support_dependencies(prepared)
              deps::MouseableReaderDependencies.new(
                formatting_service: prepared.formatting_service,
                layout_service: prepared.layout_service,
                dictionary_availability: prepared.dictionary_availability,
                ui_component_factory: prepared.ui_component_factory,
                ui_state_reader: prepared.reader_runtime_context
              ).validate!
            end
            private_class_method :build_mouse_support_dependencies

            def reader_intent_handler_factory(reader_session_store:)
              ->(controller) { build_reader_intent_handler(controller, reader_session_store) }
            end
            private_class_method :reader_intent_handler_factory

            def build_reader_intent_handler(controller, reader_session_store)
              runtime = Shoko::Adapters::Input::Controllers::Reader::IntentRuntimeBridge.new(
                reader_controller: controller
              )

              Shoko::Application::UseCases::ReaderIntentHandler.new(
                navigation_service: controller.navigation_service,
                bookmark_service: controller.bookmark_service,
                reader_session_store: reader_session_store,
                reader_display_control: runtime,
                reader_popup_control: runtime,
                reader_dictionary_control: runtime,
                reader_search_control: runtime,
                reader_annotation_editor_control: runtime,
                reader_lifecycle_control: runtime,
                application_exit_control: runtime
              )
            end
            private_class_method :build_reader_intent_handler

            def deps
              Shoko::Adapters::Input::Controllers::Dependencies
            end
            private_class_method :deps
          end
        end
      end
    end
  end
end
