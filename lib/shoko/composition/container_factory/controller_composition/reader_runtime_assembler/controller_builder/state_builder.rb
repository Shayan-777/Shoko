# frozen_string_literal: true

module Shoko
  module Bootstrap
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
                  .merge(doc: context.doc, path: controller.path)
              end
              private_class_method :state_dependencies

              def state_session_dependencies(context)
                {
                  reader_state: context.reader_state_reader,
                  config_reader: context.config_reader,
                  ui_state: context.ui_state_reader,
                  sidebar_state: context.sidebar_state_reader,
                  reader_session_mutator: context.reader_session_mutator,
                  terminal_service: context.terminal_service,
                  page_calculator: context.page_calculator,
                  layout_service: context.layout_service,
                  process_control: context.process_control,
                }
              end
              private_class_method :state_session_dependencies

              def state_repository_dependencies(context)
                {
                  progress_repository: context.progress_repository,
                  bookmark_repository: context.bookmark_repository,
                }
              end
              private_class_method :state_repository_dependencies

              def state_service_dependencies(context)
                {
                  rendered_content_reader: context.rendered_content_reader,
                  annotation_service: context.annotation_service,
                  logger: context.logger,
                  navigation_service: context.navigation_service,
                  bookmark_service: context.bookmark_service,
                  notification_service: context.notification_service,
                  coordinate_service: context.coordinate_service,
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
