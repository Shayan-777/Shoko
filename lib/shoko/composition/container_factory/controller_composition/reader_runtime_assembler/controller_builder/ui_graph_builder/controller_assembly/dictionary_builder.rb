# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          module ControllerBuilder
            module UiGraphBuilder
              module ControllerAssembly
                # Builds the dictionary controller and its runtime dependency graph.
                module DictionaryBuilder
                  module_function

                  def build(build_context)
                    deps = Shoko::Adapters::Input::Controllers::DictionaryController::Dependencies.new(
                      **dependencies(build_context)
                    ).validate!
                    Shoko::Adapters::Input::Controllers::DictionaryController.new(deps: deps)
                  end

                  def dependencies(build_context)
                    runtime_context = build_context.runtime_context
                    dictionary_state_dependencies(runtime_context)
                      .merge(dictionary_controller_dependencies(build_context))
                      .merge(dictionary_service_dependencies(runtime_context))
                      .merge(dictionary_ui_dependencies(runtime_context))
                      .merge(dictionary_platform_dependencies(runtime_context))
                  end
                  private_class_method :dependencies

                  def dictionary_state_dependencies(runtime_context)
                    {
                      reader_state: runtime_context.services.reader_state_reader,
                      config_reader: runtime_context.state.app_config_store,
                      sidebar_state: runtime_context.services.reader_state_reader,
                      reader_session_mutator: runtime_context.state.reader_session_mutator,
                      rendered_content_reader: runtime_context.state.rendered_content_reader,
                    }
                  end
                  private_class_method :dictionary_state_dependencies

                  def dictionary_controller_dependencies(build_context)
                    {
                      input_controller: build_context.input_controller,
                      reader_controller: build_context.controller,
                      ui_controller: nil,
                    }
                  end
                  private_class_method :dictionary_controller_dependencies

                  def dictionary_service_dependencies(runtime_context)
                    {
                      dictionary_service: runtime_context.services.dictionary_service,
                      dictionary_catalog_service: runtime_context.services.dictionary_catalog_service,
                      selection_service: runtime_context.services.selection_service,
                      notification_service: runtime_context.services.notification_service,
                      settings_service: runtime_context.services.settings_service,
                      dictionary_availability: runtime_context.services.dictionary_availability,
                      dictionary_storage: runtime_context.services.dictionary_storage,
                    }
                  end
                  private_class_method :dictionary_service_dependencies

                  def dictionary_ui_dependencies(runtime_context)
                    {
                      layout_service: runtime_context.ui.layout_service,
                      layout_metrics: runtime_context.ui.layout_metrics,
                      ui_component_factory: runtime_context.ui.ui_component_factory,
                      dictionary_ui_session: runtime_context.ui.dictionary_ui_session,
                    }
                  end
                  private_class_method :dictionary_ui_dependencies

                  def dictionary_platform_dependencies(runtime_context)
                    {
                      document: runtime_context.platform.doc,
                      clock: runtime_context.platform.clock,
                      logger: runtime_context.platform.logger,
                      terminal_service: runtime_context.platform.terminal_service,
                    }
                  end
                  private_class_method :dictionary_platform_dependencies
                end
              end
            end
          end
        end
      end
    end
  end
end
