# frozen_string_literal: true

require_relative 'resolved_dependencies'
require_relative 'runtime_preparation'
require_relative 'dependency_set'
require_relative 'controller_factory'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderBuilder
          # Reader composition facade from staged dependency resolution to controller creation.
          module Assembly
            module_function

            def build_controller(container:, epub_path:, preloaded_document:, background_worker:)
              resolved = ResolvedDependencies.resolve(
                container: container,
                preloaded_document: preloaded_document,
                background_worker: background_worker
              )
              prepared = RuntimePreparation.prepare(resolved)
              build_artifacts = DependencySet.build(prepared)

              ControllerFactory.build(epub_path: epub_path, prepared: prepared, build_artifacts: build_artifacts)
            end
          end
        end
      end
    end
  end
end
