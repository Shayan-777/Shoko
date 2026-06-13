# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          # Builds render coordinator and frame pipeline.
          module RenderBuilder
            module_function

            def build(controller:, context:, pagination_coordinator:, ui_controller:, anchor_resolver:)
              context.ui.rendering_factory.create_reader_render_coordinator(
                reader_dependencies: render_dependencies(
                  controller: controller,
                  context: context,
                  pagination_coordinator: pagination_coordinator,
                  ui_controller: ui_controller,
                  anchor_resolver: anchor_resolver
                )
              )
            end

            def render_dependencies(controller:, context:, pagination_coordinator:, ui_controller:, anchor_resolver:)
              context_dependencies(context)
                .merge(
                  controller: controller,
                  frame_coordinator: build_frame_coordinator(context),
                  render_pipeline: build_render_pipeline(context),
                  ui_controller: ui_controller,
                  pagination: pagination_coordinator,
                  anchor_resolver: anchor_resolver
                )
            end
            private_class_method :render_dependencies

            def context_dependencies(context)
              context_state_dependencies(context).merge(context_service_dependencies(context))
            end
            private_class_method :context_dependencies

            def context_state_dependencies(context)
              {
                observer_registry: context.state.observer_registry,
                ui_state_reader: context.state.reader_runtime_context,
                terminal_service: context.platform.terminal_service,
                doc: context.platform.doc,
                reader_dependencies: context.reader_ui_dependencies,
                render_state_writer: context.reader_ui_dependencies&.render_state_writer,
                config_reader: context.state.app_config_store,
                view_model_builder_factory: context.reader_ui_dependencies&.view_model_builder_factory,
                reader_state_reader: context.services.reader_state_reader,
              }
            end
            private_class_method :context_state_dependencies

            def context_service_dependencies(context)
              {
                wrapping_service: context.ui.wrapping_service,
                coordinate_service: context.services.coordinate_service,
                notification_service: context.services.notification_service,
                logger: context.platform.logger,
              }
            end
            private_class_method :context_service_dependencies

            def build_frame_coordinator(context)
              context.ui.rendering_factory.create_frame_coordinator(
                terminal_service: context.platform.terminal_service,
                terminal_state_writer: context.state.reader_session_mutator,
                ui_state_reader: context.state.reader_runtime_context
              )
            end
            private_class_method :build_frame_coordinator

            def build_render_pipeline(context)
              context.ui.rendering_factory.create_render_pipeline(
                reader_state_reader: context.services.reader_state_reader,
                logger: context.platform.logger
              )
            end
            private_class_method :build_render_pipeline
          end
        end
      end
    end
  end
end
