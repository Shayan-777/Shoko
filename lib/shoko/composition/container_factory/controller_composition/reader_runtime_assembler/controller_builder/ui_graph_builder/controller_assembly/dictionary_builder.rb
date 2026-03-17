# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          module ControllerBuilder
            module UiGraphBuilder
              module ControllerAssembly
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
                    {
                      reader_state: runtime_context.state.reader_session_store,
                      config_reader: runtime_context.state.app_config_store,
                      sidebar_state: runtime_context.state.reader_session_store,
                      reader_session_mutator: runtime_context.state.reader_session_mutator,
                      input_controller: build_context.input_controller,
                      layout_service: runtime_context.ui.layout_service,
                      reader_controller: build_context.controller,
                      document: runtime_context.platform.doc,
                      ui_controller: nil,
                      clock: runtime_context.platform.clock,
                      layout_metrics: runtime_context.ui.layout_metrics,
                      dictionary_service: runtime_context.services.dictionary_service,
                      dictionary_catalog_service: runtime_context.services.dictionary_catalog_service,
                      ui_component_factory: runtime_context.ui.ui_component_factory,
                      logger: runtime_context.platform.logger,
                      selection_service: runtime_context.services.selection_service,
                      rendered_content_reader: runtime_context.state.rendered_content_reader,
                      notification_service: runtime_context.services.notification_service,
                      settings_service: runtime_context.services.settings_service,
                      dictionary_availability: runtime_context.services.dictionary_availability,
                      dictionary_storage: runtime_context.services.dictionary_storage,
                      dictionary_ui_session: runtime_context.ui.dictionary_ui_session,
                      terminal_service: runtime_context.platform.terminal_service,
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
