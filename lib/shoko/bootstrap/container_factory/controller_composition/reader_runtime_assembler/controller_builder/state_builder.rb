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
                session = context.session
                {
                  reader_state: session.reader_state_reader,
                  config_reader: session.config_reader,
                  ui_state: session.ui_state_reader,
                  sidebar_state: session.sidebar_state_reader,
                  state_writer: session.state_writer,
                  terminal_service: session.terminal_service,
                  page_calculator: session.page_calculator,
                  layout_service: session.layout_service,
                  process_control: session.process_control,
                }
              end
              private_class_method :state_session_dependencies

              def state_repository_dependencies(context)
                {
                  progress_repository: context.persistence.progress_repository,
                  bookmark_repository: context.persistence.bookmark_repository,
                }
              end
              private_class_method :state_repository_dependencies

              def state_service_dependencies(context)
                services = context.services
                {
                  rendered_content_reader: services.rendered_content_reader,
                  annotation_service: services.annotation_service,
                  logger: services.logger,
                  navigation_service: services.navigation_service,
                  bookmark_service: services.bookmark_service,
                  notification_service: services.notification_service,
                  coordinate_service: services.coordinate_service,
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
