# frozen_string_literal: true

module Shoko
  module Bootstrap
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          module ControllerBuilder
            module UiGraphBuilder
              # Builds sidebar/dictionary/search/annotation/ui controllers.
              module ControllerAssembly
                module_function

                def build_sidebar_controller(build_context)
                  deps = Shoko::Adapters::Input::Controllers::SidebarController::Dependencies.new(
                    **sidebar_dependencies(build_context)
                  ).validate!
                  Shoko::Adapters::Input::Controllers::SidebarController.new(deps: deps)
                end

                def build_dictionary_controller(build_context)
                  deps = Shoko::Adapters::Input::Controllers::DictionaryController::Dependencies.new(
                    **dictionary_dependencies(build_context)
                  ).validate!
                  Shoko::Adapters::Input::Controllers::DictionaryController.new(deps: deps)
                end

                def build_annotation_controller(build_context)
                  deps = Shoko::Adapters::Input::Controllers::AnnotationOverlayController::Dependencies.build(
                    **annotation_dependencies(build_context)
                  )
                  Shoko::Adapters::Input::Controllers::AnnotationOverlayController.new(deps: deps)
                end

                def build_in_book_search_controller(build_context)
                  Shoko::Adapters::Input::Controllers::InBookSearchController.new(
                    **in_book_search_dependencies(build_context)
                  )
                end

                def build_ui_controller(build_context, controller_set)
                  deps = Shoko::Adapters::Input::Controllers::UIController::Dependencies.new(
                    **ui_dependencies(build_context, controller_set)
                  ).validate!
                  Shoko::Adapters::Input::Controllers::UIController.new(deps: deps)
                end

                def sidebar_dependencies(build_context)
                  runtime_context = build_context.runtime_context
                  session = runtime_context.session
                  {
                    reader_state: session.reader_state_reader,
                    config_reader: session.config_reader,
                    state_writer: session.state_writer,
                    sidebar_state: session.sidebar_state_reader,
                    ui_state: session.ui_state_reader,
                    document: runtime_context.doc,
                    state_controller: build_context.state_controller,
                    ui_controller: nil,
                  }.merge(sidebar_service_dependencies(runtime_context.services, session))
                end
                private_class_method :sidebar_dependencies

                def sidebar_service_dependencies(services, session)
                  {
                    navigation_service: services.navigation_service,
                    bookmark_service: services.bookmark_service,
                    notification_service: services.notification_service,
                    formatting_service: services.formatting_service,
                    layout_service: session.layout_service,
                  }
                end
                private_class_method :sidebar_service_dependencies

                def dictionary_dependencies(build_context)
                  runtime_context = build_context.runtime_context
                  session = runtime_context.session
                  services = runtime_context.services
                  dictionary_state_dependencies(build_context, session, runtime_context.doc)
                    .merge(dictionary_service_dependencies(services))
                    .merge(dictionary_runtime_dependencies(session))
                end
                private_class_method :dictionary_dependencies

                def dictionary_state_dependencies(build_context, session, document)
                  {
                    reader_state: session.reader_state_reader,
                    config_reader: session.config_reader,
                    sidebar_state: session.sidebar_state_reader,
                    state_writer: session.state_writer,
                    input_controller: build_context.input_controller,
                    layout_service: session.layout_service,
                    reader_controller: build_context.controller,
                    document: document,
                    ui_controller: nil,
                    clock: session.clock,
                  }
                end
                private_class_method :dictionary_state_dependencies

                def dictionary_service_dependencies(services)
                  {
                    layout_metrics: services.layout_metrics,
                    dictionary_service: services.dictionary_service,
                    dictionary_catalog_service: services.dictionary_catalog_service,
                    ui_component_factory: services.ui_component_factory,
                    logger: services.logger,
                    selection_service: services.selection_service,
                    rendered_content_reader: services.rendered_content_reader,
                    notification_service: services.notification_service,
                    settings_service: services.settings_service,
                    dictionary_availability: services.dictionary_availability,
                    dictionary_storage: services.dictionary_storage,
                    dictionary_ui_session: services.dictionary_ui_session,
                  }
                end
                private_class_method :dictionary_service_dependencies

                def dictionary_runtime_dependencies(session)
                  { terminal_service: session.terminal_service }
                end
                private_class_method :dictionary_runtime_dependencies

                def annotation_dependencies(build_context)
                  runtime_context = build_context.runtime_context
                  session = runtime_context.session
                  services = runtime_context.services
                  {
                    reader_state: session.reader_state_reader,
                    state_writer: session.state_writer,
                    state_controller: build_context.state_controller,
                    input_controller: build_context.input_controller,
                    annotation_service: services.annotation_service,
                    dictionary_service: services.dictionary_service,
                    annotation_overlay_ui_session: services.annotation_overlay_ui_session,
                    notification_service: services.notification_service,
                    logger: services.logger,
                  }
                end
                private_class_method :annotation_dependencies

                def in_book_search_dependencies(build_context)
                  runtime_context = build_context.runtime_context
                  session = runtime_context.session
                  services = runtime_context.services
                  {
                    reader_state: session.reader_state_reader,
                    state_writer: session.state_writer,
                    search_service: services.in_book_search_service,
                    input_controller: build_context.input_controller,
                    reader_controller: build_context.controller,
                    state_controller: build_context.state_controller,
                    in_book_search_ui_session: services.in_book_search_ui_session,
                    notification_service: services.notification_service,
                    logger: services.logger,
                    clock: session.clock,
                  }
                end
                private_class_method :in_book_search_dependencies

                def ui_dependencies(build_context, controller_set)
                  runtime_context = build_context.runtime_context
                  session = runtime_context.session
                  services = runtime_context.services
                  ui_state_dependencies(build_context, session)
                    .merge(ui_controller_dependencies(controller_set))
                    .merge(ui_service_dependencies(build_context, services))
                end
                private_class_method :ui_dependencies

                def ui_state_dependencies(build_context, session)
                  {
                    reader_state: session.reader_state_reader,
                    config_reader: session.config_reader,
                    state_writer: session.state_writer,
                    sidebar_state: session.sidebar_state_reader,
                    ui_state: session.ui_state_reader,
                    input_controller: build_context.input_controller,
                    reader_controller: build_context.controller,
                  }
                end
                private_class_method :ui_state_dependencies

                def ui_controller_dependencies(controller_set)
                  {
                    sidebar_controller: controller_set.sidebar_controller,
                    dictionary_controller: controller_set.dictionary_controller,
                    annotation_controller: controller_set.annotation_controller,
                    in_book_search_controller: controller_set.in_book_search_controller,
                  }
                end
                private_class_method :ui_controller_dependencies

                def ui_service_dependencies(build_context, services)
                  {
                    notification_service: services.notification_service,
                    selection_service: services.selection_service,
                    rendered_content_reader: services.rendered_content_reader,
                    clipboard_service: build_context.controller.clipboard_service,
                    ui_component_factory: services.ui_component_factory,
                    annotation_service: services.annotation_service,
                    logger: services.logger,
                  }
                end
                private_class_method :ui_service_dependencies
              end
            end
          end
        end
      end
    end
  end
end
