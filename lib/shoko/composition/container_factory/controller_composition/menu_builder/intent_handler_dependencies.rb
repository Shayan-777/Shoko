# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module MenuBuilder
          # Shared keyword groups for MenuIntentHandler wiring.
          module IntentHandlerDependencies
            private

            def menu_intent_capability_dependencies(runtime)
              {
                menu_browse_inspection: runtime,
                menu_download_selection: runtime,
                menu_annotation_control: runtime,
              }
            end

            def menu_intent_workflow_dependencies(menu)
              {
                reader_launch_service: menu.state_controller,
                download_workflow: menu.state_controller,
                dictionary_workflow: menu.state_controller,
                translator_workflow: menu.state_controller,
                rss_reader_workflow: menu.state_controller,
                annotation_workflow: menu.state_controller,
              }
            end

            def menu_intent_service_dependencies(menu, context)
              {
                settings_service: menu.settings_service,
                annotation_service: menu.annotation_service,
                catalog: menu.catalog,
                menu_transient_store: context.menu_transient_store,
                logger: context.logger,
              }
            end
          end
        end
      end
    end
  end
end
