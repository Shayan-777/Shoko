# frozen_string_literal: true

require_relative 'controller_builder/state_builder'
require_relative 'controller_builder/ui_graph_builder'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          # Builds reader runtime controllers around a reader controller instance.
          module ControllerBuilder
            BuiltControllers = Data.define(
              :ui_controller,
              :state_controller,
              :input_controller,
              :dictionary_controller,
              :annotation_controller,
              :in_book_search_controller
            )

            module_function

            def build(controller:, context:, anchor_resolver:)
              state_controller = StateBuilder.build(controller:, context:, anchor_resolver:)
              graph = UiGraphBuilder.build(controller:, context:, state_controller:)

              BuiltControllers.new(
                ui_controller: graph.ui_controller,
                state_controller: state_controller,
                input_controller: graph.input_controller,
                dictionary_controller: graph.dictionary_controller,
                annotation_controller: graph.annotation_controller,
                in_book_search_controller: graph.in_book_search_controller
              )
            end
          end
        end
      end
    end
  end
end
