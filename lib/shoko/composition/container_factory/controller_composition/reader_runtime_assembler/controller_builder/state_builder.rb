# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          module ControllerBuilder
            # Builds the reader state controller.
            module StateBuilder
              module_function

              def build(controller:, context:)
                deps = Shoko::Adapters::Input::Controllers::StateController::Dependencies.new(
                  **state_dependencies(controller, context)
                ).validate!

                Shoko::Adapters::Input::Controllers::StateController.new(deps: deps)
              end

              def state_dependencies(controller, context)
                state_session_dependencies(context)
                  .merge(state_repository_dependencies(context))
                  .merge(state_service_dependencies(context))
                  .merge(doc: context.platform.doc, document_reader: -> { controller.doc }, path: controller.path)
              end
              private_class_method :state_dependencies

              def state_session_dependencies(context)
                {
                  reader_state: context.state.reader_session_store,
                  config_reader: context.state.app_config_store,
                  ui_state: context.state.reader_runtime_context,
                  sidebar_state: context.state.reader_session_store,
                  reader_session_mutator: context.state.reader_session_mutator,
                  terminal_service: context.platform.terminal_service,
                  page_calculator: context.platform.page_calculator,
                  layout_service: context.ui.layout_service,
                  process_control: context.platform.process_control,
                }
              end
              private_class_method :state_session_dependencies

              def state_repository_dependencies(context)
                {
                  progress_repository: context.services.progress_repository,
                  bookmark_repository: context.services.bookmark_repository,
                }
              end
              private_class_method :state_repository_dependencies

              def state_service_dependencies(context)
                {
                  rendered_content_reader: context.state.rendered_content_reader,
                  annotation_service: context.services.annotation_service,
                  logger: context.platform.logger,
                  navigation_service: context.services.navigation_service,
                  bookmark_service: context.services.bookmark_service,
                  notification_service: context.services.notification_service,
                  coordinate_service: context.services.coordinate_service,
                }
              end
              private_class_method :state_service_dependencies
            end
          end
        end
      end
    end
  end
end
