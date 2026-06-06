# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          module ControllerBuilder
            module UiGraphBuilder
              module ControllerAssembly
                # Builds the reader UI controller that coordinates sidebar and overlays.
                module UiBuilder
                  module_function

                  def build(build_context, controller_set)
                    dependencies_class = Shoko::Adapters::Input::Controllers::UIController::Dependencies
                    deps = dependencies_class.build(**dependencies(build_context, controller_set)).validate!
                    Shoko::Adapters::Input::Controllers::UIController.new(deps: deps)
                  end

                  def dependencies(build_context, controller_set)
                    runtime_context = build_context.runtime_context
                    ui_state_dependencies(runtime_context)
                      .merge(ui_controller_dependencies(build_context, controller_set))
                      .merge(ui_service_dependencies(runtime_context))
                      .merge(ui_platform_dependencies(build_context, runtime_context))
                  end
                  private_class_method :dependencies

                  def ui_state_dependencies(runtime_context)
                    {
                      reader_state: runtime_context.services.reader_state_reader,
                      config_reader: runtime_context.state.app_config_store,
                      reader_session_mutator: runtime_context.state.reader_session_mutator,
                      sidebar_state: runtime_context.services.reader_state_reader,
                      ui_state: runtime_context.state.reader_runtime_context,
                      rendered_content_reader: runtime_context.state.rendered_content_reader,
                    }
                  end
                  private_class_method :ui_state_dependencies

                  def ui_controller_dependencies(build_context, controller_set)
                    {
                      input_controller: build_context.input_controller,
                      reader_controller: build_context.controller,
                      sidebar_controller: controller_set.sidebar_controller,
                      dictionary_controller: controller_set.dictionary_controller,
                      annotation_controller: controller_set.annotation_controller,
                      in_book_search_controller: controller_set.in_book_search_controller,
                      toc_controller: controller_set.toc_controller,
                    }
                  end
                  private_class_method :ui_controller_dependencies

                  def ui_service_dependencies(runtime_context)
                    {
                      notification_service: runtime_context.services.notification_service,
                      selection_service: runtime_context.services.selection_service,
                      translation_service: runtime_context.services.translation_service,
                      ui_component_factory: runtime_context.ui.ui_component_factory,
                      annotation_service: runtime_context.services.annotation_service,
                    }
                  end
                  private_class_method :ui_service_dependencies

                  def ui_platform_dependencies(build_context, runtime_context)
                    {
                      clipboard_service: build_context.controller.clipboard_service,
                      logger: runtime_context.platform.logger,
                    }
                  end
                  private_class_method :ui_platform_dependencies
                end
              end
            end
          end
        end
      end
    end
  end
end
