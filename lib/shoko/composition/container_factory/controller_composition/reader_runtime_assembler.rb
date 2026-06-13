# frozen_string_literal: true

require 'shoko/adapters/input/controllers/reader/runtime_types'
require 'shoko/application/services/annotations/chapter_stream_source'
require 'shoko/application/services/annotations/anchor_resolver'
require_relative 'reader_runtime_assembler/runtime_context'
require_relative 'reader_runtime_assembler/pagination_builder'
require_relative 'reader_runtime_assembler/controller_builder'
require_relative 'reader_runtime_assembler/render_builder'
require_relative 'reader_runtime_assembler/observer_wiring'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        # Assembles runtime components for reader controller composition.
        module ReaderRuntimeAssembler
          module_function

          def call(controller:, context:)
            anchor_resolver = build_anchor_resolver(controller: controller, context: context)
            pagination_coordinator = PaginationBuilder.build(controller: controller, context: context)
            controllers = ControllerBuilder.build(
              controller: controller, context: context, anchor_resolver: anchor_resolver
            )
            render_coordinator = build_render_coordinator(
              controller: controller,
              context: context,
              pagination_coordinator: pagination_coordinator,
              ui_controller: controllers.ui_controller,
              anchor_resolver: anchor_resolver
            )
            ObserverWiring.wire(controller: controller, context: context)
            build_runtime_components(controllers, pagination_coordinator, render_coordinator, anchor_resolver)
          end

          # One resolver shared across capture (notes), jump (state controller),
          # and highlight (overlay) so they agree on geometry and share its
          # per-layout chapter-stream cache. The document is late-bound through
          # the controller because cached books load it after the graph builds.
          def build_anchor_resolver(controller:, context:)
            stream_source = Shoko::Application::Services::Annotations::ChapterStreamSource.new(
              document_provider: -> { controller.doc },
              chapter_formatter: context.ui.formatting_service,
              layout_service: context.ui.layout_service,
              reader_runtime_context: context.state.reader_runtime_context,
              config_reader: context.state.app_config_store,
              line_wrapper: context.ui.wrapping_service,
              logger: context.platform.logger
            )
            Shoko::Application::Services::Annotations::AnchorResolver.new(
              chapter_stream_source: stream_source,
              logger: context.platform.logger
            )
          end
          private_class_method :build_anchor_resolver

          def build_render_coordinator(controller:, context:, pagination_coordinator:, ui_controller:, anchor_resolver:)
            RenderBuilder.build(
              controller: controller,
              context: context,
              pagination_coordinator: pagination_coordinator,
              ui_controller: ui_controller,
              anchor_resolver: anchor_resolver
            )
          end
          private_class_method :build_render_coordinator

          def build_runtime_components(controllers, pagination_coordinator, render_coordinator, anchor_resolver)
            Shoko::Adapters::Input::Controllers::Reader::RuntimeTypes::RuntimeComponents.new(
              ui_controller: controllers.ui_controller,
              state_controller: controllers.state_controller,
              input_controller: controllers.input_controller,
              pagination_coordinator: pagination_coordinator,
              render_coordinator: render_coordinator,
              anchor_resolver: anchor_resolver
            )
          end
          private_class_method :build_runtime_components
        end
      end
    end
  end
end
