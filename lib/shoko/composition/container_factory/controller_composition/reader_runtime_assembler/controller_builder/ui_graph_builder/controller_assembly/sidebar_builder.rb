# frozen_string_literal: true

module Shoko
  module Bootstrap
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          module ControllerBuilder
            module UiGraphBuilder
              module ControllerAssembly
                module SidebarBuilder
                  module_function

                  def build(build_context)
                    deps = Shoko::Adapters::Input::Controllers::SidebarController::Dependencies.new(
                      **dependencies(build_context)
                    ).validate!
                    Shoko::Adapters::Input::Controllers::SidebarController.new(deps: deps)
                  end

                  def dependencies(build_context)
                    runtime_context = build_context.runtime_context
                    {
                      reader_state: runtime_context.reader_state_reader,
                      config_reader: runtime_context.config_reader,
                      reader_session_mutator: runtime_context.reader_session_mutator,
                      sidebar_state: runtime_context.sidebar_state_reader,
                      ui_state: runtime_context.ui_state_reader,
                      document: runtime_context.doc,
                      state_controller: build_context.state_controller,
                      ui_controller: nil,
                      navigation_service: runtime_context.navigation_service,
                      bookmark_service: runtime_context.bookmark_service,
                      notification_service: runtime_context.notification_service,
                      formatting_service: runtime_context.formatting_service,
                      layout_service: runtime_context.layout_service,
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
