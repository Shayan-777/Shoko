# frozen_string_literal: true

require_relative '../../adapters/ui/dependency_sets'
require_relative 'controller_composition/menu_builder'

module Shoko
  module Composition
    module ContainerFactory
      # Builds fully-wired application controllers.
      module ControllerComposition
        include MenuBuilder

        def build_reader_controller(container, epub_path, preloaded_document: nil, background_worker: nil)
          ensure_reader_builder_loaded!
          ReaderBuilder.instance_method(:build_reader_controller).bind_call(
            self,
            container,
            epub_path,
            preloaded_document: preloaded_document,
            background_worker: background_worker
          )
        end

        def build_reader_runtime_components(controller:, runtime_context:)
          ensure_reader_builder_loaded!
          ReaderBuilder.instance_method(:build_reader_runtime_components).bind_call(
            self,
            controller: controller,
            runtime_context: runtime_context
          )
        end
        private :build_reader_runtime_components

        private

        def ensure_reader_builder_loaded!
          return if const_defined?(:ReaderBuilder, false)

          require_relative '../../adapters/input/controllers/dependencies/reader_controller_dependencies'
          require_relative 'controller_composition/reader_builder'
        end
      end
    end
  end
end
