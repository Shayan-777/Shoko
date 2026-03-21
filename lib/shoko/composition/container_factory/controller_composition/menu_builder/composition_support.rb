# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module MenuBuilder
          # Builds the shared composition context used by the menu controller wiring.
          module CompositionSupport
            private

            def build_composition_context(context)
              MenuStateControllerComposer::CompositionContext.new(
                **menu_state_context(context),
                **runtime_service_context(context),
                **workflow_service_context(context)
              )
            end

            def menu_state_context(context)
              {
                menu_state_reader: context.menu_state_reader,
                menu_session_mutator: context.menu_session_mutator,
                reader_state_reader: context.reader_state_reader,
                app_config_store: context.app_config_store,
                reader_session_store: context.reader_session_store,
                menu_session_store: context.menu_session_store,
                menu_transient_store: context.menu_transient_store,
                reader_runtime_context: context.reader_runtime_context,
              }
            end

            def runtime_service_context(context)
              {
                pagination_orchestrator: build_pagination_orchestrator(context),
                catalog_service: context.catalog_service,
                logger: context.logger,
                runtime_config: context.runtime_config,
                file_probe: context.file_probe,
                path_ops: context.path_ops,
                clock: context.clock,
                translation_service: context.translation_service,
                reader_launch_state: context.reader_launch_state,
                menu_launch_state: context.menu_launch_state,
                download_service: context.download_service,
                text_sanitizer: context.text_sanitizer,
              }
            end

            def workflow_service_context(context)
              {
                dictionary_catalog_service: context.dictionary_catalog_service,
                dictionary_storage: context.dictionary_storage,
                annotation_service: context.annotation_service,
                cache_pointer_resolver: context.cache_pointer_resolver,
                reader_document_locator: context.reader_document_locator,
                document_loader: context.document_loader,
                background_worker_builder: context.background_worker_builder,
                recent_files_repository: context.recent_files_repository,
                page_calculator: context.page_calculator,
                pagination_cache_preloader: context.pagination_cache_preloader,
              }
            end

            def build_pagination_orchestrator(context)
              Shoko::Shared::LazyProxy.new do
                require_relative '../../../../application/services/pagination/pagination_orchestrator'
                Shoko::Application::Services::Pagination::PaginationOrchestrator.new(
                  reader_runtime_context: context.reader_runtime_context,
                  pagination_cache: context.pagination_cache,
                  instrumentation: context.instrumentation,
                  logger: context.logger
                )
              end
            end
          end
        end
      end
    end
  end
end
