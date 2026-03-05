# frozen_string_literal: true

module Shoko
  module Bootstrap
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          # Builds pagination coordinator for reader runtime composition.
          module PaginationBuilder
            module_function

            def build(controller:, context:)
              Shoko::Application::Services::Pagination::PaginationCoordinator.new(
                **pagination_dependencies(controller: controller, context: context)
              )
            end

            def pagination_dependencies(controller:, context:)
              pagination_state_dependencies(context)
                .merge(pagination_runtime_dependencies(controller: controller, context: context))
            end
            private_class_method :pagination_dependencies

            def pagination_state_dependencies(context)
              session = context.session
              persistence = context.persistence
              {
                doc: context.doc,
                page_calculator: session.page_calculator,
                layout_service: session.layout_service,
                ui_state_reader: session.ui_state_reader,
                pagination_cache: persistence.pagination_cache,
                notification_writer: persistence.notification_writer,
                config_reader: session.config_reader,
                reader_state_reader: session.reader_state_reader,
                pagination_state_writer: session.state_writer,
                ui_loading_writer: session.state_writer,
                sidebar_state_reader: session.sidebar_state_reader,
              }
            end
            private_class_method :pagination_state_dependencies

            def pagination_runtime_dependencies(controller:, context:)
              services = context.services
              {
                logger: services.logger,
                reader_render_requester: build_render_requester(controller, services.logger),
                async_executor: services.async_executor,
                display_capabilities: services.display_capabilities,
                instrumentation: services.instrumentation,
              }
            end
            private_class_method :pagination_runtime_dependencies

            def build_render_requester(controller, logger)
              Shoko::Adapters::Input::Controllers::Reader::RenderRequesterBridge.new(
                controller: controller,
                logger: logger
              )
            end
            private_class_method :build_render_requester
          end
        end
      end
    end
  end
end
