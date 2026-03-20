# frozen_string_literal: true

module Shoko
  module Composition
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
              pagination_platform_dependencies(context).merge(pagination_store_dependencies(context))
            end
            private_class_method :pagination_state_dependencies

            def pagination_platform_dependencies(context)
              {
                doc: context.platform.doc,
                page_calculator: context.platform.page_calculator,
                layout_service: context.ui.layout_service,
                pagination_cache: context.services.pagination_cache,
                notification_writer: context.state.notification_writer,
              }
            end
            private_class_method :pagination_platform_dependencies

            def pagination_store_dependencies(context)
              {
                app_config_store: context.state.app_config_store,
                reader_session_store: context.state.reader_session_store,
                reader_state_reader: context.services.reader_state_reader,
                reader_view_state_store: context.services.reader_view_state_store,
                reader_pagination_store: context.services.reader_pagination_store,
                reader_runtime_context: context.state.reader_runtime_context,
              }
            end
            private_class_method :pagination_store_dependencies

            def pagination_runtime_dependencies(controller:, context:)
              {
                logger: context.platform.logger,
                reader_render_requester: build_render_requester(controller, context.platform.logger),
                async_executor: context.platform.async_executor,
                instrumentation: context.platform.instrumentation,
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
