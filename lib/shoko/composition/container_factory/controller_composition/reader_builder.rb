# frozen_string_literal: true

require_relative '../../../core/services/in_book_search_service'
require_relative '../../../core/ports/outbound/background_worker_builder'
require_relative '../../../application/pending_jump_handler'
require_relative '../../../application/use_cases/reader_intent_handler'
require_relative '../../../application/services/pagination/pagination_coordinator'
require_relative '../../../adapters/input/controllers/reader/lifecycle_runner'
require_relative '../../../adapters/input/controllers/reader/intent_runtime_bridge'
require_relative '../../../adapters/input/controllers/reader/render_requester_bridge'
require_relative '../../../adapters/input/controllers/mouseable_reader'
require_relative '../../../adapters/input/controllers/ui_controller'
require_relative '../../../adapters/input/controllers/state_controller'
require_relative '../../../adapters/input/controllers/sidebar_controller'
require_relative '../../../adapters/input/controllers/dictionary_controller'
require_relative '../../../adapters/input/controllers/annotation_overlay_controller'
require_relative '../../../adapters/input/controllers/in_book_search_controller'
require_relative 'reader_builder/assembly'
require_relative 'reader_runtime_assembler'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderBuilder
          # Build a fully-wired MouseableReader controller.
          def build_reader_controller(container, epub_path, preloaded_document: nil, background_worker: nil)
            Assembly.build_controller(
              container: container,
              epub_path: epub_path,
              preloaded_document: preloaded_document,
              background_worker: background_worker
            )
          end

          def build_reader_runtime_components(controller:, runtime_context:)
            ReaderRuntimeAssembler.call(
              controller: controller,
              context: runtime_context
            )
          end
          private :build_reader_runtime_components
        end
      end
    end
  end
end
