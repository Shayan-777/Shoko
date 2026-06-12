# frozen_string_literal: true

require 'shoko/application/services/async_result_relay'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          module ControllerBuilder
            # Builds non-state reader controllers and the UI controller graph.
            # Deliberately one flat, boring wiring file (constitution §IV): each
            # build_* function names the concrete controller it constructs and
            # the dependency hash it feeds in.
            module UiGraphBuilder
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

              module_function

              def build(controller:, context:, state_controller:)
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
                {
                  reader_state: runtime_context.services.reader_state_reader,
                  reader_session_mutator: runtime_context.state.reader_session_mutator,
                  translation_service: runtime_context.services.translation_service,
                  translator_ui_session: runtime_context.ui.translator_ui_session,
                  input_controller: build_context.input_controller,
                  selection_service: runtime_context.services.selection_service,
                  rendered_content_reader: runtime_context.state.rendered_content_reader,
                  notification_service: runtime_context.services.notification_service,
                  logger: runtime_context.platform.logger,
                }
              end
              private_class_method :translator_dependencies

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
                  .merge(ui_platform_dependencies(build_context, runtime_context))
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
