# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          module ControllerBuilder
            module UiGraphBuilder
              module ControllerAssembly
                # Builds the reader sidebar controller and its live document wiring.
                module SidebarBuilder
                  module_function

                  def build(build_context)
                    dependencies_class = Shoko::Adapters::Input::Controllers::SidebarController::Dependencies
                    deps = dependencies_class.build(**dependencies(build_context)).validate!
                    Shoko::Adapters::Input::Controllers::SidebarController.new(deps: deps)
                  end

                  def dependencies(build_context)
                    runtime_context = build_context.runtime_context
                    sidebar_runtime_dependencies(runtime_context).merge(sidebar_controller_dependencies(build_context))
                  end
                  private_class_method :dependencies

                  def sidebar_runtime_dependencies(runtime_context)
                    sidebar_state_dependencies(runtime_context)
                      .merge(sidebar_service_dependencies(runtime_context))
                      .merge(sidebar_ui_dependencies(runtime_context))
                      .merge(sidebar_platform_dependencies(runtime_context))
                  end
                  private_class_method :sidebar_runtime_dependencies

                  def sidebar_state_dependencies(runtime_context)
                    {
                      reader_state: runtime_context.services.reader_state_reader,
                      config_reader: runtime_context.state.app_config_store,
                      reader_session_mutator: runtime_context.state.reader_session_mutator,
                      sidebar_state: runtime_context.services.reader_state_reader,
                      ui_state: runtime_context.state.reader_runtime_context,
                    }
                  end
                  private_class_method :sidebar_state_dependencies

                  def sidebar_service_dependencies(runtime_context)
                    {
                      navigation_service: runtime_context.services.navigation_service,
                      bookmark_service: runtime_context.services.bookmark_service,
                      notification_service: runtime_context.services.notification_service,
                    }
                  end
                  private_class_method :sidebar_service_dependencies

                  def sidebar_ui_dependencies(runtime_context)
                    {
                      formatting_service: runtime_context.ui.formatting_service,
                      layout_service: runtime_context.ui.layout_service,
                    }
                  end
                  private_class_method :sidebar_ui_dependencies

                  def sidebar_platform_dependencies(runtime_context)
                    {
                      document: runtime_context.platform.doc,
                    }
                  end
                  private_class_method :sidebar_platform_dependencies

                  def sidebar_controller_dependencies(build_context)
                    {
                      document_reader: -> { build_context.controller.doc },
                      state_controller: build_context.state_controller,
                      ui_controller: nil,
                    }
                  end
                  private_class_method :sidebar_controller_dependencies
                end
              end
            end
          end
        end
      end
    end
  end
end
