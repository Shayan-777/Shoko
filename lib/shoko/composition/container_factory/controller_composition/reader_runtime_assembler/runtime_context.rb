# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          ReaderPlatformContext = Data.define(
            :doc,
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

          RuntimeContext = Data.define(:platform, :state, :ui, :services, :reader_ui_dependencies)
        end
      end
    end
  end
end
