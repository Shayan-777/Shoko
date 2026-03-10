# frozen_string_literal: true

require_relative '../../../core/services/in_book_search_service'
require_relative '../../../core/ports/outbound/background_worker_builder'
require_relative '../../../application/pending_jump_handler'
require_relative '../../../application/use_cases/reader_intent_handler'
require_relative '../../../application/services/pagination/pagination_coordinator'
require_relative '../../../adapters/input/controllers/reader/lifecycle_runner'
require_relative '../../../adapters/input/controllers/reader/intent_runtime_bridge'
require_relative '../../../adapters/input/controllers/reader/render_requester_bridge'
require_relative '../../../adapters/input/controllers/ui_controller'
require_relative '../../../adapters/input/controllers/state_controller'
require_relative '../../../adapters/input/controllers/sidebar_controller'
require_relative '../../../adapters/input/controllers/dictionary_controller'
require_relative '../../../adapters/input/controllers/annotation_overlay_controller'
require_relative '../../../adapters/input/controllers/in_book_search_controller'
require_relative 'reader_builder/dependency_resolution'
require_relative 'reader_builder/runtime_support'
require_relative 'reader_builder/composition_factory'
require_relative 'reader_runtime_assembler'

module Shoko
  module Bootstrap
    module ContainerFactory
      module ControllerComposition
        module ReaderBuilder
          # Build a fully-wired MouseableReader controller.
          def build_reader_controller(container, epub_path, preloaded_document: nil, background_worker: nil)
            resolved = resolve_reader_inputs(
              container,
              preloaded_document: preloaded_document,
              background_worker: background_worker
            )
            resolved = prepare_reader_runtime_inputs(resolved)
            reader_ui_dependencies = build_reader_ui_dependencies(resolved)
            sync_reader_launch_state!(resolved)
            reader_deps = build_reader_controller_dependencies(
              resolved,
              reader_ui_dependencies: reader_ui_dependencies
            )
            runtime_context = build_reader_runtime_context(
              resolved,
              reader_ui_dependencies: reader_ui_dependencies
            )

            build_reader_controller_instance(epub_path, resolved, reader_deps, runtime_context)
          end

          def build_reader_runtime_components(controller:, runtime_context:)
            ReaderRuntimeAssembler.call(
              controller: controller,
              context: runtime_context
            )
          end
          private :build_reader_runtime_components

          def resolve_many(container, keys)
            keys.to_h do |key|
              [key, container.resolve(key)]
            end
          end
          private :resolve_many

          def build_background_worker(background_worker_builder:, logger:, name:)
            return nil unless background_worker_builder

            unless background_worker_builder.is_a?(Shoko::Core::Ports::Outbound::BackgroundWorkerBuilder)
              raise ArgumentError,
                    'background_worker_builder must implement Core::Ports::Outbound::BackgroundWorkerBuilder'
            end

            background_worker_builder.build(logger: logger, name: name)
          end
          private :build_background_worker

          def prefer_worker_executor(async_executor:, worker:)
            return async_executor unless worker
            return worker if async_executor.nil?
            return worker if inline_executor?(async_executor)

            async_executor
          end
          private :prefer_worker_executor

          def inline_executor?(executor)
            return false unless executor
            return false unless defined?(Shoko::Core::Services::InlineExecutor)

            executor.is_a?(Shoko::Core::Services::InlineExecutor)
          end
          private :inline_executor?
        end
      end
    end
  end
end
