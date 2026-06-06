# frozen_string_literal: true

require_relative 'ui_graph_builder/controller_assembly'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          module ControllerBuilder
            # Builds non-state reader controllers and the UI controller graph.
            module UiGraphBuilder
              Graph = Data.define(
                :ui_controller,
                :input_controller,
                :sidebar_controller,
                :dictionary_controller,
                :annotation_controller,
                :in_book_search_controller
              )

              BuildContext = Data.define(:controller, :runtime_context, :state_controller, :input_controller)

              ControllerSet = Data.define(
                :sidebar_controller,
                :dictionary_controller,
                :annotation_controller,
                :in_book_search_controller,
                :toc_controller
              )

              module_function

              def build(controller:, context:, state_controller:)
                ui_controller = nil
                input_controller = build_input_controller(context, -> { ui_controller })
                build_context = BuildContext.new(
                  controller: controller,
                  runtime_context: context,
                  state_controller: state_controller,
                  input_controller: input_controller
                )
                controller_set = build_controller_set(build_context)
                ui_controller = ControllerAssembly.build_ui_controller(build_context, controller_set)
                build_graph(ui_controller, input_controller, controller_set)
              end

              def build_input_controller(context, ui_controller_provider)
                context.ui.input_system_factory.create_reader_input_controller(
                  reader_state_reader: context.services.reader_state_reader,
                  ui_controller_provider: ui_controller_provider
                )
              end
              private_class_method :build_input_controller

              def build_controller_set(build_context)
                ControllerSet.new(
                  sidebar_controller: ControllerAssembly.build_sidebar_controller(build_context),
                  dictionary_controller: ControllerAssembly.build_dictionary_controller(build_context),
                  annotation_controller: ControllerAssembly.build_annotation_controller(build_context),
                  in_book_search_controller: ControllerAssembly.build_in_book_search_controller(build_context),
                  toc_controller: ControllerAssembly.build_toc_controller(build_context)
                )
              end
              private_class_method :build_controller_set

              def build_graph(ui_controller, input_controller, controller_set)
                Graph.new(
                  ui_controller: ui_controller,
                  input_controller: input_controller,
                  sidebar_controller: controller_set.sidebar_controller,
                  dictionary_controller: controller_set.dictionary_controller,
                  annotation_controller: controller_set.annotation_controller,
                  in_book_search_controller: controller_set.in_book_search_controller
                )
              end
              private_class_method :build_graph
            end
          end
        end
      end
    end
  end
end
