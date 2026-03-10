# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          RuntimeContext = Data.define(
            :doc,
            :terminal_service,
            :page_calculator,
            :layout_service,
            :ui_state_reader,
            :sidebar_state_reader,
            :config_reader,
            :reader_state_reader,
            :reader_session_mutator,
            :observer_registry,
            :clock,
            :process_control,
            :app_config_store,
            :reader_session_store,
            :reader_runtime_context,
            :logger,
            :navigation_service,
            :bookmark_service,
            :annotation_service,
            :coordinate_service,
            :notification_service,
            :async_executor,
            :display_capabilities,
            :instrumentation,
            :dictionary_service,
            :dictionary_catalog_service,
            :settings_service,
            :dictionary_availability,
            :dictionary_storage,
            :layout_metrics,
            :rendered_content_reader,
            :selection_service,
            :ui_component_factory,
            :in_book_search_service,
            :dictionary_ui_session,
            :in_book_search_ui_session,
            :annotation_overlay_ui_session,
            :formatting_service,
            :wrapping_service,
            :input_system_factory,
            :rendering_factory,
            :progress_repository,
            :bookmark_repository,
            :pagination_cache,
            :notification_writer,
            :reader_ui_dependencies
          )
        end
      end
    end
  end
end
