# frozen_string_literal: true

module Shoko
  module Bootstrap
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          SessionBundle = Data.define(
            :terminal_service,
            :page_calculator,
            :layout_service,
            :ui_state_reader,
            :sidebar_state_reader,
            :config_reader,
            :reader_state_reader,
            :state_writer,
            :command_bus,
            :observer_registry,
            :clock,
            :process_control
          )

          ServiceBundle = Data.define(
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
            :wrapping_service
          )

          UiBundle = Data.define(
            :input_system_factory,
            :rendering_factory
          )

          PersistenceBundle = Data.define(
            :progress_repository,
            :bookmark_repository,
            :pagination_cache,
            :notification_writer
          )

          RuntimeContext = Data.define(
            :doc,
            :session,
            :services,
            :ui,
            :persistence,
            :reader_ui_dependencies
          )
        end
      end
    end
  end
end
