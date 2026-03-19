# frozen_string_literal: true

require_relative '../../../adapters/input/controllers/reader/runtime_types'
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
            pagination_coordinator = PaginationBuilder.build(controller: controller, context: context)
            controllers = ControllerBuilder.build(controller: controller, context: context)
            render_coordinator = build_render_coordinator(
              controller: controller,
              context: context,
              pagination_coordinator: pagination_coordinator,
              ui_controller: controllers.ui_controller
            )
            ObserverWiring.wire(controller: controller, context: context)
            build_runtime_components(controllers, pagination_coordinator, render_coordinator)
          end

          def build_render_coordinator(controller:, context:, pagination_coordinator:, ui_controller:)
            RenderBuilder.build(
              controller: controller,
              context: context,
              pagination_coordinator: pagination_coordinator,
              ui_controller: ui_controller
            )
          end
          private_class_method :build_render_coordinator

          def build_runtime_components(controllers, pagination_coordinator, render_coordinator)
            Shoko::Adapters::Input::Controllers::Reader::RuntimeTypes::RuntimeComponents.new(
              ui_controller: controllers.ui_controller,
              state_controller: controllers.state_controller,
              input_controller: controllers.input_controller,
              pagination_coordinator: pagination_coordinator,
              render_coordinator: render_coordinator
            )
          end
          private_class_method :build_runtime_components
        end
      end
    end
  end
end
