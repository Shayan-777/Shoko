# frozen_string_literal: true

module Shoko
  module Bootstrap
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
                      reader_state: runtime_context.reader_state_reader,
                      config_reader: runtime_context.config_reader,
                      sidebar_state: runtime_context.sidebar_state_reader,
                      reader_session_mutator: runtime_context.reader_session_mutator,
                      input_controller: build_context.input_controller,
                      layout_service: runtime_context.layout_service,
                      reader_controller: build_context.controller,
                      document: runtime_context.doc,
                      ui_controller: nil,
                      clock: runtime_context.clock,
                      layout_metrics: runtime_context.layout_metrics,
                      dictionary_service: runtime_context.dictionary_service,
                      dictionary_catalog_service: runtime_context.dictionary_catalog_service,
                      ui_component_factory: runtime_context.ui_component_factory,
                      logger: runtime_context.logger,
                      selection_service: runtime_context.selection_service,
                      rendered_content_reader: runtime_context.rendered_content_reader,
                      notification_service: runtime_context.notification_service,
                      settings_service: runtime_context.settings_service,
                      dictionary_availability: runtime_context.dictionary_availability,
                      dictionary_storage: runtime_context.dictionary_storage,
                      dictionary_ui_session: runtime_context.dictionary_ui_session,
                      terminal_service: runtime_context.terminal_service,
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
