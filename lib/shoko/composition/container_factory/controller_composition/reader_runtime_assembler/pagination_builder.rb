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
              {
                doc: context.doc,
                page_calculator: context.page_calculator,
                layout_service: context.layout_service,
                pagination_cache: context.pagination_cache,
                notification_writer: context.notification_writer,
                app_config_store: context.app_config_store,
                reader_session_store: context.reader_session_store,
                reader_runtime_context: context.reader_runtime_context,
              }
            end
            private_class_method :pagination_state_dependencies

            def pagination_runtime_dependencies(controller:, context:)
              {
                logger: context.logger,
                reader_render_requester: build_render_requester(controller, context.logger),
                async_executor: context.async_executor,
                instrumentation: context.instrumentation,
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
