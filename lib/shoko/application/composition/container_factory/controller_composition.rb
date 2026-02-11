# frozen_string_literal: true

require_relative '../../../adapters/output/ui/dependency_sets'
require_relative '../dependencies/reader_controller_dependencies'
require_relative '../dependencies/menu_controller_dependencies'
require_relative 'controller_composition/reader_builder'
require_relative 'controller_composition/menu_builder'

module Shoko
  module Application
    module Composition
      module ContainerFactory
        # Builds fully-wired application controllers.
        module ControllerComposition
          include ReaderBuilder
          include MenuBuilder
        end
      end
    end
  end
end
