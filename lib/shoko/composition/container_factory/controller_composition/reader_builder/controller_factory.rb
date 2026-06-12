# frozen_string_literal: true

require 'shoko/adapters/input/controllers/mouseable_reader'
require_relative '../reader_runtime_assembler'
require_relative 'dependency_set'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderBuilder
          # Instantiates the concrete reader controller from staged build artifacts.
          module ControllerFactory
            module_function

            def build(epub_path:, prepared:, build_artifacts:)
              Shoko::Adapters::Input::Controllers::MouseableReader.new(
                epub_path,
                **controller_arguments(
                  prepared: prepared,
                  controller_dependencies: build_artifacts.controller_dependencies,
                  runtime_context: build_artifacts.runtime_context
                )
              )
            end

            def controller_arguments(prepared:, controller_dependencies:, runtime_context:)
              {
                core: controller_dependencies.core,
                state: controller_dependencies.state,
                services: controller_dependencies.services,
                runtime_boot: controller_dependencies.runtime_boot,
                runtime_startup: controller_dependencies.runtime_startup,
                mouse_support: controller_dependencies.mouse_support,
                render_state_writer: prepared.render_state_writer,
                mouse_handler: prepared.input_system_factory.create_mouse_handler,
                runtime_components_factory: build_runtime_components_factory(runtime_context),
              }
            end
            private_class_method :controller_arguments

            def build_runtime_components_factory(runtime_context)
              lambda do |controller_instance|
                ReaderRuntimeAssembler.call(controller: controller_instance, context: runtime_context)
              end
            end
            private_class_method :build_runtime_components_factory
          end
        end
      end
    end
  end
end
