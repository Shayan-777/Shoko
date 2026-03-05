# frozen_string_literal: true

module Shoko
  module Bootstrap
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          # Builds render coordinator and frame pipeline.
          module RenderBuilder
            module_function

            def build(controller:, context:, pagination_coordinator:, ui_controller:)
              context.ui.rendering_factory.create_reader_render_coordinator(
                reader_dependencies: render_dependencies(
                  controller: controller,
                  context: context,
                  pagination_coordinator: pagination_coordinator,
                  ui_controller: ui_controller
                )
              )
            end

            def render_dependencies(controller:, context:, pagination_coordinator:, ui_controller:)
              context_dependencies(context)
                .merge(
                  controller: controller,
                  frame_coordinator: build_frame_coordinator(context),
                  render_pipeline: build_render_pipeline(context),
                  ui_controller: ui_controller,
                  pagination: pagination_coordinator
                )
            end
            private_class_method :render_dependencies

            def context_dependencies(context)
              context_state_dependencies(context)
                .merge(context_service_dependencies(context))
            end
            private_class_method :context_dependencies

            def context_state_dependencies(context)
              session = context.session
              {
                observer_registry: session.observer_registry,
                ui_state_reader: session.ui_state_reader,
                terminal_service: session.terminal_service,
                doc: context.doc,
                reader_dependencies: context.reader_ui_dependencies,
                render_state_writer: context.reader_ui_dependencies&.render_state_writer,
                config_reader: session.config_reader,
                view_model_builder_factory: context.reader_ui_dependencies&.view_model_builder_factory,
                reader_state_reader: session.reader_state_reader,
              }
            end
            private_class_method :context_state_dependencies

            def context_service_dependencies(context)
              services = context.services
              {
                wrapping_service: services.wrapping_service,
                coordinate_service: services.coordinate_service,
                notification_service: services.notification_service,
                logger: services.logger,
              }
            end
            private_class_method :context_service_dependencies

            def build_frame_coordinator(context)
              session = context.session
              context.ui.rendering_factory.create_frame_coordinator(
                terminal_service: session.terminal_service,
                state_writer: session.state_writer,
                ui_state_reader: session.ui_state_reader
              )
            end
            private_class_method :build_frame_coordinator

            def build_render_pipeline(context)
              session = context.session
              context.ui.rendering_factory.create_render_pipeline(
                reader_state_reader: session.reader_state_reader,
                logger: context.services.logger
              )
            end
            private_class_method :build_render_pipeline
          end
        end
      end
    end
  end
end
