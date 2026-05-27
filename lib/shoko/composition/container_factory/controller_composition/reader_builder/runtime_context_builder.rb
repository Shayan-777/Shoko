# frozen_string_literal: true

require_relative '../reader_runtime_assembler/runtime_context'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderBuilder
          # Converts prepared reader builder inputs into runtime assembler contexts.
          module RuntimeContextBuilder
            SERVICE_CONTEXT_FIELDS = {
              navigation_service: :navigation_service,
              bookmark_service: :bookmark_service,
              annotation_service: :annotation_service,
              coordinate_service: :coordinate_service,
              notification_service: :notification_service,
              selection_service: :selection_service,
              translation_service: :translation_service,
              dictionary_service: :dictionary_service,
              dictionary_catalog_service: :dictionary_catalog_service,
              settings_service: :settings_service,
              dictionary_availability: :dictionary_availability,
              dictionary_storage: :dictionary_storage,
              progress_repository: :progress_repository,
              bookmark_repository: :bookmark_repository,
              pagination_cache: :pagination_cache,
              in_book_search_service: :in_book_search_service,
              reader_state_reader: :reader_state_reader,
            }.freeze

            module_function

            def build(prepared, reader_ui_dependencies:)
              ReaderRuntimeAssembler::RuntimeContext.new(
                platform: build_platform_context(prepared),
                state: build_state_context(prepared),
                ui: build_ui_context(prepared),
                services: build_service_context(prepared),
                reader_ui_dependencies: reader_ui_dependencies
              )
            end

            def build_platform_context(prepared)
              ReaderRuntimeAssembler::ReaderPlatformContext.new(
                doc: prepared.document,
                terminal_service: prepared.terminal_service,
                terminal_session: prepared.terminal_session,
                page_calculator: prepared.page_calculator,
                clock: prepared.clock,
                process_control: prepared.process_control,
                async_executor: prepared.async_executor,
                display_capabilities: prepared.display_capabilities,
                instrumentation: prepared.instrumentation,
                logger: prepared.logger
              )
            end
            private_class_method :build_platform_context

            def build_state_context(prepared)
              ReaderRuntimeAssembler::ReaderStateContext.new(
                reader_session_store: prepared.reader_session_store,
                reader_session_mutator: prepared.reader_session_mutator,
                app_config_store: prepared.app_config_store,
                observer_registry: prepared.observer_registry,
                reader_runtime_context: prepared.reader_runtime_context,
                rendered_content_reader: prepared.rendered_content_reader,
                notification_writer: prepared.notification_writer,
                reader_component_registry: prepared.reader_component_registry
              )
            end
            private_class_method :build_state_context

            def build_ui_context(prepared)
              ReaderRuntimeAssembler::ReaderUiContext.new(
                layout_service: prepared.layout_service,
                layout_metrics: prepared.layout_metrics,
                wrapping_service: prepared.wrapping_service,
                formatting_service: prepared.formatting_service,
                ui_component_factory: prepared.ui_component_factory,
                input_system_factory: prepared.input_system_factory,
                rendering_factory: prepared.rendering_factory,
                dictionary_ui_session: prepared.dictionary_ui_session,
                in_book_search_ui_session: prepared.in_book_search_ui_session,
                annotation_overlay_ui_session: prepared.annotation_overlay_ui_session
              )
            end
            private_class_method :build_ui_context

            def build_service_context(prepared)
              ReaderRuntimeAssembler::ReaderServiceContext.new(
                **extract_attributes(prepared, SERVICE_CONTEXT_FIELDS),
                reader_view_state_store: prepared.reader_view_state_store,
                reader_pagination_store: prepared.reader_pagination_store
              )
            end
            private_class_method :build_service_context

            def extract_attributes(prepared, field_map)
              prepared_hash = prepared.to_h
              field_map.transform_values { |source| prepared_hash.fetch(source) }
            end
            private_class_method :extract_attributes
          end
        end
      end
    end
  end
end
