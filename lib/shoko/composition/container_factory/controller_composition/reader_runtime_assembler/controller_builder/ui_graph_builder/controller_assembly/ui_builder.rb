# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          module ControllerBuilder
            module UiGraphBuilder
              module ControllerAssembly
                module UiBuilder
                  module_function

                  def build(build_context, controller_set)
                    deps = Shoko::Adapters::Input::Controllers::UIController::Dependencies.new(
                      **dependencies(build_context, controller_set)
                    ).validate!
                    Shoko::Adapters::Input::Controllers::UIController.new(deps: deps)
                  end

                  def dependencies(build_context, controller_set)
                    runtime_context = build_context.runtime_context
                    {
                      reader_state: runtime_context.state.reader_session_store,
                      config_reader: runtime_context.state.app_config_store,
                      reader_session_mutator: runtime_context.state.reader_session_mutator,
                      sidebar_state: runtime_context.state.reader_session_store,
                      ui_state: runtime_context.state.reader_runtime_context,
                      input_controller: build_context.input_controller,
                      reader_controller: build_context.controller,
                      sidebar_controller: controller_set.sidebar_controller,
                      dictionary_controller: controller_set.dictionary_controller,
                      annotation_controller: controller_set.annotation_controller,
                      in_book_search_controller: controller_set.in_book_search_controller,
                      notification_service: runtime_context.services.notification_service,
                      selection_service: runtime_context.services.selection_service,
                      rendered_content_reader: runtime_context.state.rendered_content_reader,
                      clipboard_service: build_context.controller.clipboard_service,
                      ui_component_factory: runtime_context.ui.ui_component_factory,
                      annotation_service: runtime_context.services.annotation_service,
                      logger: runtime_context.platform.logger,
                    }
                  end
                  private_class_method :dependencies
                end
              end
            end
          end
        end
      end
    end
  end
end
