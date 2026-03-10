# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          # Builds render coordinator and frame pipeline.
          module RenderBuilder
            module_function

            def build(controller:, context:, pagination_coordinator:, ui_controller:)
              context.rendering_factory.create_reader_render_coordinator(
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
              {
                observer_registry: context.observer_registry,
                ui_state_reader: context.ui_state_reader,
                terminal_service: context.terminal_service,
                doc: context.doc,
                reader_dependencies: context.reader_ui_dependencies,
                render_state_writer: context.reader_ui_dependencies&.render_state_writer,
                config_reader: context.config_reader,
                view_model_builder_factory: context.reader_ui_dependencies&.view_model_builder_factory,
                reader_state_reader: context.reader_state_reader,
              }
            end
            private_class_method :context_state_dependencies

            def context_service_dependencies(context)
              {
                wrapping_service: context.wrapping_service,
                coordinate_service: context.coordinate_service,
                notification_service: context.notification_service,
                logger: context.logger,
              }
            end
            private_class_method :context_service_dependencies

            def build_frame_coordinator(context)
              context.rendering_factory.create_frame_coordinator(
                terminal_service: context.terminal_service,
                terminal_state_writer: context.reader_session_mutator,
                ui_state_reader: context.ui_state_reader
              )
            end
            private_class_method :build_frame_coordinator

            def build_render_pipeline(context)
              context.rendering_factory.create_render_pipeline(
                reader_state_reader: context.reader_state_reader,
                logger: context.logger
              )
            end
            private_class_method :build_render_pipeline
          end
        end
      end
    end
  end
end
