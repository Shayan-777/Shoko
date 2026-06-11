# frozen_string_literal: true

require_relative '../../../../../../../application/services/async_result_relay'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          module ControllerBuilder
            module UiGraphBuilder
              module ControllerAssembly
                # Builds overlay controllers that share the reader runtime state.
                module OverlayBuilder
                  module_function

                  def build_annotation(build_context)
                    deps = Shoko::Adapters::Input::Controllers::AnnotationOverlayController::Dependencies.build(
                      **annotation_dependencies(build_context)
                    )
                    Shoko::Adapters::Input::Controllers::AnnotationOverlayController.new(deps: deps)
                  end

                  def build_in_book_search(build_context)
                    Shoko::Adapters::Input::Controllers::InBookSearchController.new(
                      **in_book_search_dependencies(build_context)
                    )
                  end

                  def build_toc(build_context)
                    Shoko::Adapters::Input::Controllers::TocLookupController.new(
                      **toc_dependencies(build_context)
                    )
                  end

                  def build_translator(build_context)
                    relay = build_translator_relay(build_context)
                    controller = Shoko::Adapters::Input::Controllers::TranslatorController.new(
                      **translator_dependencies(build_context),
                      async_relay: relay
                    )
                    register_async_relay(build_context, relay)
                    controller
                  end

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

                  def build_notes(build_context)
                    Shoko::Adapters::Input::Controllers::NotesLookupController.new(
                      **notes_dependencies(build_context)
                    )
                  end

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

                  # Reuses the sidebar's href→line-offset resolver so sub-chapter TOC
                  # entries land on their precise in-chapter anchor. It reads the
                  # full-width (sidebar-invisible) layout, which matches what the TOC
                  # overlay renders over.
                  def build_toc_anchor_resolver(build_context)
                    runtime_context = build_context.runtime_context
                    Shoko::Adapters::Input::Controllers::Sidebar::AnchorResolver.new(
                      document_reader: -> { build_context.controller.doc },
                      formatting_service: runtime_context.ui.formatting_service,
                      layout_service: runtime_context.ui.layout_service,
                      ui_state_reader: runtime_context.state.reader_runtime_context,
                      config_reader: runtime_context.state.app_config_store,
                      sidebar_state_reader: runtime_context.services.reader_state_reader
                    )
                  end
                  private_class_method :build_toc_anchor_resolver
                end
              end
            end
          end
        end
      end
    end
  end
end
