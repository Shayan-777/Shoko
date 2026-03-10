# frozen_string_literal: true

require_relative '../../../adapters/input/controllers/reader/runtime_types'
require_relative 'reader_runtime_assembler/runtime_context'
require_relative 'reader_runtime_assembler/pagination_builder'
require_relative 'reader_runtime_assembler/controller_builder'
require_relative 'reader_runtime_assembler/render_builder'
require_relative 'reader_runtime_assembler/observer_wiring'

module Shoko
  module Bootstrap
    module ContainerFactory
      module ControllerComposition
        # Assembles runtime components for reader controller composition.
        module ReaderRuntimeAssembler
          module_function

          def call(controller:, context:)
            pagination_coordinator = PaginationBuilder.build(controller: controller, context: context)
            controllers = ControllerBuilder.build(controller: controller, context: context)
            render_coordinator = RenderBuilder.build(
              controller: controller,
              context: context,
              pagination_coordinator: pagination_coordinator,
              ui_controller: controllers.ui_controller
            )
            ObserverWiring.wire(controller: controller, context: context)

            Shoko::Adapters::Input::Controllers::Reader::RuntimeTypes::RuntimeComponents.new(
              ui_controller: controllers.ui_controller,
              state_controller: controllers.state_controller,
              input_controller: controllers.input_controller,
              pagination_coordinator: pagination_coordinator,
              render_coordinator: render_coordinator
            )
          end
        end
      end
    end
  end
end
