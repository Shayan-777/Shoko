# frozen_string_literal: true

module Shoko
  module Bootstrap
    module ContainerFactory
      module ControllerComposition
        module ReaderBuilder
          module_function

          def build_reader_controller_dependencies(resolved, reader_ui_dependencies:)
            values = resolved.merge(
              intent_handler_factory: build_reader_intent_handler_factory,
              background_worker: resolved[:worker],
              reader_launch_state: resolved[:session_context],
              reader_ui_dependencies: reader_ui_dependencies
            )
            deps = Shoko::Adapters::Input::Controllers::Dependencies

            {
              core: deps::ReaderControllerCoreDependencies.build(**values).validate!,
              state: deps::ReaderControllerStateDependencies.build(**values).validate!,
              services: deps::ReaderControllerServiceDependencies.build(**values).validate!,
              runtime_boot: deps::ReaderRuntimeBootDependencies.build(**values).validate!,
              runtime_startup: deps::ReaderRuntimeStartupDependencies.build(**values).validate!,
              mouse_support: deps::MouseableReaderDependencies.build(**values).validate!
            }
          end

          def build_reader_runtime_context(resolved, reader_ui_dependencies:)
            ReaderRuntimeAssembler::RuntimeContext.new(
              doc: resolved[:document],
              terminal_service: resolved[:terminal_service],
              page_calculator: resolved[:page_calculator],
              layout_service: resolved[:layout_service],
              ui_state_reader: resolved[:ui_state_reader],
              sidebar_state_reader: resolved[:sidebar_state_reader],
              config_reader: resolved[:config_reader],
              reader_state_reader: resolved[:reader_state_reader],
              reader_session_mutator: resolved[:reader_session_mutator],
              observer_registry: resolved[:observer_registry],
              clock: resolved[:clock],
              process_control: resolved[:process_control],
              app_config_store: resolved[:app_config_store],
              reader_session_store: resolved[:reader_session_store],
              reader_runtime_context: resolved[:reader_runtime_context_port],
              logger: resolved[:logger],
              navigation_service: resolved[:navigation_service],
              bookmark_service: resolved[:bookmark_service],
              annotation_service: resolved[:annotation_service],
              coordinate_service: resolved[:coordinate_service],
              notification_service: resolved[:notification_service],
              async_executor: resolved[:async_executor],
              display_capabilities: resolved[:display_capabilities],
              instrumentation: resolved[:instrumentation],
              dictionary_service: resolved[:dictionary_service],
              dictionary_catalog_service: resolved[:dictionary_catalog_service],
              settings_service: resolved[:settings_service],
              dictionary_availability: resolved[:dictionary_availability],
              dictionary_storage: resolved[:dictionary_storage],
              layout_metrics: resolved[:layout_metrics],
              rendered_content_reader: resolved[:rendered_content_reader],
              selection_service: resolved[:selection_service],
              ui_component_factory: resolved[:ui_component_factory],
              in_book_search_service: resolved[:in_book_search_service],
              dictionary_ui_session: resolved[:dictionary_ui_session],
              in_book_search_ui_session: resolved[:in_book_search_ui_session],
              annotation_overlay_ui_session: resolved[:annotation_overlay_ui_session],
              formatting_service: resolved[:formatting_service],
              wrapping_service: resolved[:wrapping_service],
              input_system_factory: resolved[:input_system_factory],
              rendering_factory: resolved[:rendering_factory],
              progress_repository: resolved[:progress_repository],
              bookmark_repository: resolved[:bookmark_repository],
              pagination_cache: resolved[:pagination_cache],
              notification_writer: resolved[:notification_writer],
              reader_ui_dependencies: reader_ui_dependencies
            )
          end

          def build_reader_controller_instance(epub_path, resolved, reader_deps, runtime_context)
            Shoko::Adapters::Input::Controllers::MouseableReader.new(
              epub_path,
              core: reader_deps.fetch(:core),
              state: reader_deps.fetch(:state),
              services: reader_deps.fetch(:services),
              runtime_boot: reader_deps.fetch(:runtime_boot),
              runtime_startup: reader_deps.fetch(:runtime_startup),
              mouse_support: reader_deps.fetch(:mouse_support),
              render_state_writer: resolved[:render_state_writer],
              mouse_handler: resolved[:input_system_factory].create_mouse_handler,
              runtime_components_factory: lambda { |controller_instance|
                build_reader_runtime_components(
                  controller: controller_instance,
                  runtime_context: runtime_context
                )
              }
            )
          end

          def build_reader_intent_handler_factory
            lambda { |controller|
              runtime = Shoko::Adapters::Input::Controllers::Reader::IntentRuntimeBridge.new(
                reader_controller: controller
              )
              Shoko::Application::UseCases::ReaderIntentHandler.new(
                navigation_service: controller.navigation_service,
                bookmark_service: controller.bookmark_service,
                reader_state_reader: controller.reader_state_reader,
                reader_runtime: runtime
              )
            }
          end
          private_class_method :build_reader_intent_handler_factory
        end
      end
    end
  end
end
