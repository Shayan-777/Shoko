# frozen_string_literal: true

require 'shoko/core/services/in_book_search_service'
require 'shoko/application/ports/outbound/background_worker_builder'
require 'shoko/application/pending_jump_handler'
require 'shoko/application/use_cases/reader_intent_handler'
require 'shoko/application/services/pagination/pagination_coordinator'
require 'shoko/adapters/input/controllers/reader/lifecycle_runner'
require 'shoko/adapters/input/controllers/reader/intent_runtime_bridge'
require 'shoko/adapters/input/controllers/reader/render_requester_bridge'
require 'shoko/adapters/input/controllers/mouseable_reader'
require 'shoko/adapters/input/controllers/ui_controller'
require 'shoko/adapters/input/controllers/state_controller'
require 'shoko/adapters/input/controllers/dictionary_controller'
require 'shoko/adapters/input/controllers/annotation_overlay_controller'
require 'shoko/adapters/input/controllers/in_book_search_controller'
require 'shoko/adapters/input/controllers/toc_lookup_controller'
require 'shoko/adapters/input/controllers/translator_controller'
require 'shoko/adapters/input/controllers/notes_lookup_controller'
require_relative 'reader_builder/resolved_dependencies'
require_relative 'reader_builder/runtime_preparation'
require_relative 'reader_builder/runtime_context_builder'
require_relative 'reader_builder/dependency_set'
require_relative 'reader_builder/controller_factory'
require_relative 'reader_builder/assembly'
require_relative 'reader_runtime_assembler'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        # Builds the reader controller and delegates runtime assembly.
        module ReaderBuilder
          def build_reader_controller(container, epub_path, preloaded_document: nil, background_worker: nil)
            Assembly.build_controller(
              container: container,
              epub_path: epub_path,
              preloaded_document: preloaded_document,
              background_worker: background_worker
            )
          end

          def build_reader_runtime_components(controller:, runtime_context:)
            ReaderRuntimeAssembler.call(controller: controller, context: runtime_context)
          end
          private :build_reader_runtime_components
        end
      end
    end
  end
end
