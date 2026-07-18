# frozen_string_literal: true

require_relative '../../adapters/ui/menu_ui_dependencies'
require_relative 'controller_composition/menu_builder'

module Shoko
  module Composition
    module ContainerFactory
      # Builds fully-wired application controllers.
      module ControllerComposition
        include MenuBuilder

        def build_reader_controller(container, epub_path, preloaded_document: nil, background_worker: nil)
          ensure_reader_builder_loaded!
          ReaderBuilder.build_controller(
            container: container,
            epub_path: epub_path,
            preloaded_document: preloaded_document,
            background_worker: background_worker
          )
        end

        private

        # The reader graph loads lazily so the menu boot path never pays for
        # it (boot-surface guardrail).
        def ensure_reader_builder_loaded!
          return if const_defined?(:ReaderBuilder, false)

          require_relative 'controller_composition/reader_builder'
        end
      end
    end
  end
end
