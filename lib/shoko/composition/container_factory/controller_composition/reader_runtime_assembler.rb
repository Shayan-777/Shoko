# frozen_string_literal: true

require 'shoko/application/services/annotations/anchor_resolver'
require 'shoko/application/services/annotations/chapter_stream_source'
require 'shoko/application/services/async_result_relay'
require 'shoko/application/services/pagination/pagination_coordinator'
require 'shoko/adapters/input/controllers/annotation_overlay_controller'
require 'shoko/adapters/input/controllers/dictionary_controller'
require 'shoko/adapters/input/controllers/in_book_search_controller'
require 'shoko/adapters/input/controllers/notes_lookup_controller'
require 'shoko/adapters/input/controllers/reader/render_requester_bridge'
require 'shoko/adapters/input/controllers/reader/runtime_types'
require 'shoko/adapters/input/controllers/reader/toc_anchor_resolver'
require 'shoko/adapters/input/controllers/state_controller'
require 'shoko/adapters/input/controllers/toc_lookup_controller'
require 'shoko/adapters/input/controllers/translator_controller'
require 'shoko/adapters/input/controllers/ui_controller'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        # Assembles the reader runtime component graph around a reader
        # controller instance: pagination coordinator, state controller, the
        # UI controller graph, render coordinator, and observer wiring.
        # Deliberately one flat, boring wiring file (constitution section 7): each
        # build_* function names the concrete collaborator it constructs and
        # the dependency hash it feeds in.
        module ReaderRuntimeAssembler
          ReaderPlatformContext = Data.define(
            :doc,
            :document_provider,
            :terminal_service,
            :terminal_session,
            :page_calculator,
            :clock,
            :process_control,
            :async_executor,
            :display_capabilities,
            :instrumentation,
            :logger
          )

          ReaderStateContext = Data.define(
            :reader_session_store,
            :reader_session_mutator,
            :app_config_store,
            :observer_registry,
            :reader_runtime_context,
            :rendered_content_reader,
            :notification_writer,
            :reader_component_registry
          )

          ReaderUiContext = Data.define(
            :layout_service,
            :layout_metrics,
            :wrapping_service,
            :formatting_service,
            :ui_component_factory,
            :input_system_factory,
            :rendering_factory,
            :dictionary_ui_session,
            :in_book_search_ui_session,
            :toc_ui_session,
            :translator_ui_session,
            :notes_ui_session,
            :annotation_overlay_ui_session
          )

          ReaderServiceContext = Data.define(
            :navigation_service,
            :bookmark_service,
            :annotation_service,
            :coordinate_service,
            :notification_service,
            :selection_service,
            :translation_service,
            :dictionary_service,
            :dictionary_catalog_service,
            :settings_service,
            :dictionary_availability,
            :dictionary_storage,
            :progress_repository,
            :bookmark_repository,
            :pagination_cache,
            :in_book_search_service,
            :reader_state_reader,
            :reader_view_state_store,
            :reader_pagination_store
          )

          RuntimeContext = Data.define(:platform, :state, :ui, :services, :render_dependencies,
                                       :view_model_builder_factory)

          # The assembled UI controller graph.
          Graph = Data.define(
            :ui_controller,
            :input_controller,
            :dictionary_controller,
            :annotation_controller,
            :in_book_search_controller
          )

          BuildContext = Data.define(:controller, :runtime_context, :state_controller, :input_controller)

          ControllerSet = Data.define(
            :dictionary_controller,
            :annotation_controller,
            :in_book_search_controller,
            :toc_controller,
            :translator_controller,
            :notes_controller
          )

          # The state + UI controllers the runtime component bundle needs.
          Controllers = Data.define(:ui_controller, :state_controller, :input_controller)

          module_function

          def call(controller:, context:)
            anchor_resolver = build_anchor_resolver(controller: controller, context: context)
            pagination_coordinator = build_pagination_coordinator(controller: controller, context: context)
            controllers = build_controllers(controller: controller, context: context, anchor_resolver: anchor_resolver)
            render_coordinator = build_render_coordinator(
              controller: controller,
              context: context,
              pagination_coordinator: pagination_coordinator,
              ui_controller: controllers.ui_controller,
              anchor_resolver: anchor_resolver
            )
            wire_observers(controller: controller, context: context)
            build_runtime_components(controllers, pagination_coordinator, render_coordinator, anchor_resolver)
          end

          def build_controllers(controller:, context:, anchor_resolver:)
            state_controller = build_state_controller(
              controller: controller, context: context, anchor_resolver: anchor_resolver
            )
            graph = build_ui_graph(controller: controller, context: context, state_controller: state_controller)
            Controllers.new(
              ui_controller: graph.ui_controller,
              state_controller: state_controller,
              input_controller: graph.input_controller
            )
          end
          private_class_method :build_controllers

          def build_runtime_components(controllers, pagination_coordinator, render_coordinator, anchor_resolver)
            Shoko::Adapters::Input::Controllers::Reader::RuntimeTypes::RuntimeComponents.new(
              ui_controller: controllers.ui_controller,
              state_controller: controllers.state_controller,
              input_controller: controllers.input_controller,
              pagination_coordinator: pagination_coordinator,
              render_coordinator: render_coordinator,
              anchor_resolver: anchor_resolver
            )
          end
          private_class_method :build_runtime_components

          # ----- anchor resolver ----------------------------------------------

          # One resolver shared across capture (notes), jump (state controller),
          # and highlight (overlay) so they agree on geometry and share its
          # per-layout chapter-stream cache. The document is late-bound through
          # the controller because cached books load it after the graph builds.
          def build_anchor_resolver(controller:, context:)
            stream_source = Shoko::Application::Services::Annotations::ChapterStreamSource.new(
              document_provider: -> { controller.doc },
              chapter_formatter: context.ui.formatting_service,
              layout_service: context.ui.layout_service,
              reader_runtime_context: context.state.reader_runtime_context,
              config_reader: context.state.app_config_store,
              line_wrapper: context.ui.wrapping_service,
              logger: context.platform.logger
            )
            Shoko::Application::Services::Annotations::AnchorResolver.new(
              chapter_stream_source: stream_source,
              logger: context.platform.logger
            )
          end
          private_class_method :build_anchor_resolver

          # ----- pagination coordinator ---------------------------------------

          def build_pagination_coordinator(controller:, context:)
            Shoko::Application::Services::Pagination::PaginationCoordinator.new(
              **pagination_dependencies(controller: controller, context: context)
            )
          end
          private_class_method :build_pagination_coordinator

          def pagination_dependencies(controller:, context:)
            pagination_platform_dependencies(context)
              .merge(pagination_store_dependencies(context))
              .merge(pagination_runtime_dependencies(controller: controller, context: context))
          end
          private_class_method :pagination_dependencies

          def pagination_platform_dependencies(context)
            {
              doc: context.platform.doc,
              document_provider: context.platform.document_provider,
              page_calculator: context.platform.page_calculator,
              layout_service: context.ui.layout_service,
              pagination_cache: context.services.pagination_cache,
              notification_writer: context.state.notification_writer,
            }
          end
          private_class_method :pagination_platform_dependencies

          def pagination_store_dependencies(context)
            {
              app_config_store: context.state.app_config_store,
              reader_session_store: context.state.reader_session_store,
              reader_state_reader: context.services.reader_state_reader,
              reader_view_state_store: context.services.reader_view_state_store,
              reader_pagination_store: context.services.reader_pagination_store,
              reader_runtime_context: context.state.reader_runtime_context,
            }
          end
          private_class_method :pagination_store_dependencies

          def pagination_runtime_dependencies(controller:, context:)
            {
              logger: context.platform.logger,
              reader_render_requester: Shoko::Adapters::Input::Controllers::Reader::RenderRequesterBridge.new(
                controller: controller
              ),
              async_executor: context.platform.async_executor,
              instrumentation: context.platform.instrumentation,
            }
          end
          private_class_method :pagination_runtime_dependencies

          # ----- state controller ---------------------------------------------

          def build_state_controller(controller:, context:, anchor_resolver:)
            dependencies_class = Shoko::Adapters::Input::Controllers::StateController::Dependencies
            deps = dependencies_class.build(
              **state_dependencies(controller, context, anchor_resolver)
            ).validate!

            Shoko::Adapters::Input::Controllers::StateController.new(deps: deps)
          end
          private_class_method :build_state_controller

          def state_dependencies(controller, context, anchor_resolver)
            state_session_dependencies(context)
              .merge(
                progress_repository: context.services.progress_repository,
                bookmark_repository: context.services.bookmark_repository
              )
              .merge(state_service_dependencies(context, anchor_resolver))
              .merge(doc: context.platform.doc, document_reader: -> { controller.doc }, path: controller.path)
          end
          private_class_method :state_dependencies

          def state_session_dependencies(context)
            {
              reader_state: context.services.reader_state_reader,
              config_reader: context.state.app_config_store,
              ui_state: context.state.reader_runtime_context,
              reader_session_mutator: context.state.reader_session_mutator,
              terminal_service: context.platform.terminal_service,
              page_calculator: context.platform.page_calculator,
              layout_service: context.ui.layout_service,
              process_control: context.platform.process_control,
            }
          end
          private_class_method :state_session_dependencies

          def state_service_dependencies(context, anchor_resolver)
            {
              rendered_content_reader: context.state.rendered_content_reader,
              annotation_service: context.services.annotation_service,
              logger: context.platform.logger,
              navigation_service: context.services.navigation_service,
              bookmark_service: context.services.bookmark_service,
              notification_service: context.services.notification_service,
              anchor_resolver: anchor_resolver,
            }
          end
          private_class_method :state_service_dependencies

          # ----- ui controller graph ------------------------------------------

          def build_ui_graph(controller:, context:, state_controller:)
            ui_controller = nil
            input_controller = build_input_controller(context, -> { ui_controller })
            build_context = BuildContext.new(
              controller: controller,
              runtime_context: context,
              state_controller: state_controller,
              input_controller: input_controller
            )
            controller_set = build_controller_set(build_context)
            ui_controller = build_ui_controller(build_context, controller_set)
            build_graph(ui_controller, input_controller, controller_set)
          end
          private_class_method :build_ui_graph

          def build_graph(ui_controller, input_controller, controller_set)
            Graph.new(
              ui_controller: ui_controller,
              input_controller: input_controller,
              dictionary_controller: controller_set.dictionary_controller,
              annotation_controller: controller_set.annotation_controller,
              in_book_search_controller: controller_set.in_book_search_controller
            )
          end
          private_class_method :build_graph

          def build_input_controller(context, ui_controller_provider)
            context.ui.input_system_factory.create_reader_input_controller(
              reader_state_reader: context.services.reader_state_reader,
              ui_controller_provider: ui_controller_provider
            )
          end
          private_class_method :build_input_controller

          def build_controller_set(build_context)
            ControllerSet.new(
              dictionary_controller: build_dictionary_controller(build_context),
              annotation_controller: build_annotation_controller(build_context),
              in_book_search_controller: build_in_book_search_controller(build_context),
              toc_controller: build_toc_controller(build_context),
              translator_controller: build_translator_controller(build_context),
              notes_controller: build_notes_controller(build_context)
            )
          end
          private_class_method :build_controller_set

          # ----- dictionary -----

          def build_dictionary_controller(build_context)
            dependencies_class = Shoko::Adapters::Input::Controllers::DictionaryController::Dependencies
            deps = dependencies_class.build(**dictionary_dependencies(build_context)).validate!
            Shoko::Adapters::Input::Controllers::DictionaryController.new(deps: deps)
          end
          private_class_method :build_dictionary_controller

          def dictionary_dependencies(build_context)
            runtime_context = build_context.runtime_context
            dictionary_state_dependencies(runtime_context)
              .merge(dictionary_controller_dependencies(build_context))
              .merge(dictionary_service_dependencies(runtime_context))
              .merge(dictionary_ui_dependencies(runtime_context))
              .merge(dictionary_platform_dependencies(runtime_context))
          end
          private_class_method :dictionary_dependencies

          def dictionary_state_dependencies(runtime_context)
            {
              reader_state: runtime_context.services.reader_state_reader,
              config_reader: runtime_context.state.app_config_store,
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

          # ----- overlays sharing the reader runtime state -----

          def build_annotation_controller(build_context)
            deps = Shoko::Adapters::Input::Controllers::AnnotationOverlayController::Dependencies.build(
              **annotation_dependencies(build_context)
            )
            Shoko::Adapters::Input::Controllers::AnnotationOverlayController.new(deps: deps)
          end
          private_class_method :build_annotation_controller

          def annotation_dependencies(build_context)
            runtime_context = build_context.runtime_context
            {
              reader_state: runtime_context.services.reader_state_reader,
              reader_session_mutator: runtime_context.state.reader_session_mutator,
              state_controller: build_context.state_controller,
              input_controller: build_context.input_controller,
              annotation_service: runtime_context.services.annotation_service,
              dictionary_service: runtime_context.services.dictionary_service,
              annotation_overlay_ui_session: runtime_context.ui.annotation_overlay_ui_session,
              notification_service: runtime_context.services.notification_service,
              logger: runtime_context.platform.logger,
            }
          end
          private_class_method :annotation_dependencies

          def build_in_book_search_controller(build_context)
            Shoko::Adapters::Input::Controllers::InBookSearchController.new(
              **in_book_search_dependencies(build_context)
            )
          end
          private_class_method :build_in_book_search_controller

          def in_book_search_dependencies(build_context)
            runtime_context = build_context.runtime_context
            {
              reader_state: runtime_context.services.reader_state_reader,
              reader_session_mutator: runtime_context.state.reader_session_mutator,
              search_service: runtime_context.services.in_book_search_service,
              input_controller: build_context.input_controller,
              reader_controller: build_context.controller,
              state_controller: build_context.state_controller,
              in_book_search_ui_session: runtime_context.ui.in_book_search_ui_session,
              notification_service: runtime_context.services.notification_service,
              logger: runtime_context.platform.logger,
              clock: runtime_context.platform.clock,
            }
          end
          private_class_method :in_book_search_dependencies

          def build_toc_controller(build_context)
            Shoko::Adapters::Input::Controllers::TocLookupController.new(
              **toc_dependencies(build_context)
            )
          end
          private_class_method :build_toc_controller

          def toc_dependencies(build_context)
            runtime_context = build_context.runtime_context
            {
              reader_state: runtime_context.services.reader_state_reader,
              navigation_service: runtime_context.services.navigation_service,
              state_controller: build_context.state_controller,
              document_reader: -> { build_context.controller.doc },
              toc_ui_session: runtime_context.ui.toc_ui_session,
              anchor_resolver: build_toc_anchor_resolver(build_context),
              input_controller: build_context.input_controller,
              notification_service: runtime_context.services.notification_service,
              logger: runtime_context.platform.logger,
            }
          end
          private_class_method :toc_dependencies

          # Resolves sub-chapter TOC entries to their precise in-chapter
          # anchor by reading the full-width layout, which matches what the
          # TOC overlay renders over.
          def build_toc_anchor_resolver(build_context)
            runtime_context = build_context.runtime_context
            Shoko::Adapters::Input::Controllers::Reader::TocAnchorResolver.new(
              document_reader: -> { build_context.controller.doc },
              formatting_service: runtime_context.ui.formatting_service,
              layout_service: runtime_context.ui.layout_service,
              ui_state_reader: runtime_context.state.reader_runtime_context,
              config_reader: runtime_context.state.app_config_store
            )
          end
          private_class_method :build_toc_anchor_resolver

          def build_translator_controller(build_context)
            relay = build_translator_relay(build_context)
            controller = Shoko::Adapters::Input::Controllers::TranslatorController.new(
              **translator_dependencies(build_context),
              async_relay: relay
            )
            register_async_relay(build_context, relay)
            controller
          end
          private_class_method :build_translator_controller

          # The reader controller drains this relay from its event loop
          # so translation results land on the UI thread.
          def build_translator_relay(build_context)
            runtime_context = build_context.runtime_context
            Shoko::Application::Services::AsyncResultRelay.new(
              async_executor: runtime_context.platform.async_executor,
              logger: runtime_context.platform.logger
            )
          end
          private_class_method :build_translator_relay

          def register_async_relay(build_context, relay)
            controller = build_context.controller
            return unless controller

            controller.register_async_relay(relay)
          end
          private_class_method :register_async_relay

          def translator_dependencies(build_context)
            runtime_context = build_context.runtime_context
            translator_core_dependencies(runtime_context, build_context)
              .merge(translator_support_dependencies(runtime_context, build_context))
          end
          private_class_method :translator_dependencies

          def translator_core_dependencies(runtime_context, build_context)
            {
              reader_state: runtime_context.services.reader_state_reader,
              reader_session_mutator: runtime_context.state.reader_session_mutator,
              translation_service: runtime_context.services.translation_service,
              translator_ui_session: runtime_context.ui.translator_ui_session,
              input_controller: build_context.input_controller,
            }
          end
          private_class_method :translator_core_dependencies

          def translator_support_dependencies(runtime_context, build_context)
            {
              selection_text_source: translator_selection_text_source(runtime_context),
              clipboard_service: build_context.controller.clipboard_service,
              notification_service: runtime_context.services.notification_service,
              logger: runtime_context.platform.logger,
            }
          end
          private_class_method :translator_support_dependencies

          def translator_selection_text_source(runtime_context)
            Shoko::Adapters::Input::Controllers::TranslatorController::SelectionTextSource.new(
              selection_service: runtime_context.services.selection_service,
              rendered_content_reader: runtime_context.state.rendered_content_reader
            )
          end
          private_class_method :translator_selection_text_source

          def build_notes_controller(build_context)
            Shoko::Adapters::Input::Controllers::NotesLookupController.new(
              **notes_dependencies(build_context)
            )
          end
          private_class_method :build_notes_controller

          def notes_dependencies(build_context)
            runtime_context = build_context.runtime_context
            {
              reader_state: runtime_context.services.reader_state_reader,
              reader_session_mutator: runtime_context.state.reader_session_mutator,
              state_controller: build_context.state_controller,
              notes_ui_session: runtime_context.ui.notes_ui_session,
              annotation_service: runtime_context.services.annotation_service,
              selection_service: runtime_context.services.selection_service,
              rendered_content_reader: runtime_context.state.rendered_content_reader,
              input_controller: build_context.input_controller,
              notification_service: runtime_context.services.notification_service,
              logger: runtime_context.platform.logger,
            }
          end
          private_class_method :notes_dependencies

          # ----- ui controller -----

          def build_ui_controller(build_context, controller_set)
            dependencies_class = Shoko::Adapters::Input::Controllers::UIController::Dependencies
            deps = dependencies_class.build(**ui_dependencies(build_context, controller_set)).validate!
            Shoko::Adapters::Input::Controllers::UIController.new(deps: deps)
          end
          private_class_method :build_ui_controller

          def ui_dependencies(build_context, controller_set)
            runtime_context = build_context.runtime_context
            ui_state_dependencies(runtime_context)
              .merge(ui_controller_dependencies(build_context, controller_set))
              .merge(ui_service_dependencies(runtime_context))
              .merge(
                clipboard_service: build_context.controller.clipboard_service,
                logger: runtime_context.platform.logger
              )
          end
          private_class_method :ui_dependencies

          def ui_state_dependencies(runtime_context)
            {
              reader_state: runtime_context.services.reader_state_reader,
              config_reader: runtime_context.state.app_config_store,
              reader_session_mutator: runtime_context.state.reader_session_mutator,
              ui_state: runtime_context.state.reader_runtime_context,
              rendered_content_reader: runtime_context.state.rendered_content_reader,
            }
          end
          private_class_method :ui_state_dependencies

          def ui_controller_dependencies(build_context, controller_set)
            {
              input_controller: build_context.input_controller,
              reader_controller: build_context.controller,
              dictionary_controller: controller_set.dictionary_controller,
              annotation_controller: controller_set.annotation_controller,
              in_book_search_controller: controller_set.in_book_search_controller,
              toc_controller: controller_set.toc_controller,
              translator_controller: controller_set.translator_controller,
              notes_controller: controller_set.notes_controller,
            }
          end
          private_class_method :ui_controller_dependencies

          def ui_service_dependencies(runtime_context)
            {
              notification_service: runtime_context.services.notification_service,
              selection_service: runtime_context.services.selection_service,
              ui_component_factory: runtime_context.ui.ui_component_factory,
              annotation_service: runtime_context.services.annotation_service,
            }
          end
          private_class_method :ui_service_dependencies

          # ----- render coordinator -------------------------------------------

          def build_render_coordinator(controller:, context:, pagination_coordinator:, ui_controller:,
                                       anchor_resolver:)
            context.ui.rendering_factory.create_reader_render_coordinator(
              reader_dependencies: render_dependencies(
                controller: controller,
                context: context,
                pagination_coordinator: pagination_coordinator,
                ui_controller: ui_controller,
                anchor_resolver: anchor_resolver
              )
            )
          end
          private_class_method :build_render_coordinator

          def render_dependencies(controller:, context:, pagination_coordinator:, ui_controller:, anchor_resolver:)
            render_state_dependencies(context)
              .merge(render_service_dependencies(context))
              .merge(
                controller: controller,
                frame_coordinator: build_frame_coordinator(context),
                render_pipeline: build_render_pipeline(context),
                ui_controller: ui_controller,
                pagination: pagination_coordinator,
                anchor_resolver: anchor_resolver
              )
          end
          private_class_method :render_dependencies

          def render_state_dependencies(context)
            {
              observer_registry: context.state.observer_registry,
              ui_state_reader: context.state.reader_runtime_context,
              terminal_service: context.platform.terminal_service,
              doc: context.platform.doc,
              render_dependencies: context.render_dependencies,
              render_state_writer: context.render_dependencies.render_state_writer,
              config_reader: context.state.app_config_store,
              view_model_builder_factory: context.view_model_builder_factory,
              reader_state_reader: context.services.reader_state_reader,
            }
          end
          private_class_method :render_state_dependencies

          def render_service_dependencies(context)
            {
              wrapping_service: context.ui.wrapping_service,
              coordinate_service: context.services.coordinate_service,
              notification_service: context.services.notification_service,
              logger: context.platform.logger,
            }
          end
          private_class_method :render_service_dependencies

          def build_frame_coordinator(context)
            context.ui.rendering_factory.create_frame_coordinator(
              terminal_service: context.platform.terminal_service,
              terminal_state_writer: context.state.reader_session_mutator,
              ui_state_reader: context.state.reader_runtime_context
            )
          end
          private_class_method :build_frame_coordinator

          def build_render_pipeline(context)
            context.ui.rendering_factory.create_render_pipeline(
              reader_state_reader: context.services.reader_state_reader,
              logger: context.platform.logger
            )
          end
          private_class_method :build_render_pipeline

          # ----- observers ------------------------------------------------------

          def wire_observers(controller:, context:)
            context.state.observer_registry.add_observer(
              controller,
              %i[reader mode],
              %i[reader dictionary_visible],
              %i[reader current_chapter],
              %i[reader single_page],
              %i[reader left_page],
              %i[reader current_page_index],
              %i[config theme],
              %i[config view_mode],
              %i[config line_spacing],
              %i[config page_numbering_mode],
              %i[config kitty_images]
            )
          end
          private_class_method :wire_observers
        end
      end
    end
  end
end
