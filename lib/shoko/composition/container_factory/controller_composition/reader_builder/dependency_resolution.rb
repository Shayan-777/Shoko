# frozen_string_literal: true

module Shoko
  module Bootstrap
    module ContainerFactory
      module ControllerComposition
        module ReaderBuilder
          REQUIRED_CONTAINER_KEYS = %i[
            input_system_factory
            terminal_service
            terminal_session
            page_calculator
            clipboard_service
            layout_service
            rendering_factory
            dictionary_ui_session
            in_book_search_ui_session
            annotation_overlay_ui_session
            annotation_editor_launcher
            config_view
            app_config_store
            reader_session_view
            reader_session_store
            reader_session_mutator
            reader_ui_state_view
            reader_runtime_context
            clock
            observer_registry
          ].freeze

          OPTIONAL_CONTAINER_KEYS = %i[
            instrumentation
            navigation_service
            bookmark_service
            key_classifier
            selection_service
            wrapping_service
            rendered_content_reader
            annotation_service
            render_registry
            document_loader
            coordinate_service
            reader_document_locator
            popup_position_service
            notification_service
            ui_component_factory
            layout_metrics
            dictionary_service
            dictionary_catalog_service
            settings_service
            dictionary_availability
            dictionary_storage
            runtime_config
            formatting_service
            cache_pointer_resolver
            path_ops
            background_worker_builder
            progress_repository
            bookmark_repository
            pagination_cache
            notification_writer
            async_executor
            display_capabilities
            process_control
            instrumentation_service
            pagination_cache_preloader
            render_state_writer
            logger
            view_model_builder_factory
            kitty_image_renderer
          ].freeze

          module_function

          def resolve_reader_inputs(container, preloaded_document:, background_worker:)
            required = resolve_many(container, REQUIRED_CONTAINER_KEYS)
            optional = resolve_many(container, OPTIONAL_CONTAINER_KEYS)
            session_context = container.resolve(:reader_launch_state)
            document = preloaded_document || session_context&.preloaded_document

            {
              session_context: session_context,
              document: document,
              worker: background_worker || session_context&.background_worker,
              input_system_factory: required[:input_system_factory],
              terminal_service: required[:terminal_service],
              terminal_session: required[:terminal_session],
              page_calculator: required[:page_calculator],
              clipboard_service: required[:clipboard_service],
              layout_service: required[:layout_service],
              rendering_factory: required[:rendering_factory],
              dictionary_ui_session: required[:dictionary_ui_session],
              in_book_search_ui_session: required[:in_book_search_ui_session],
              annotation_overlay_ui_session: required[:annotation_overlay_ui_session],
              annotation_editor_launcher: required[:annotation_editor_launcher],
              config_reader: required[:config_view],
              app_config_store: required[:app_config_store],
              reader_state_reader: required[:reader_session_view],
              reader_session_store: required[:reader_session_store],
              reader_session_mutator: required[:reader_session_mutator],
              ui_state_reader: required[:reader_ui_state_view],
              sidebar_state_reader: required[:reader_session_view],
              reader_runtime_context_port: required[:reader_runtime_context],
              clock: required[:clock],
              observer_registry: required[:observer_registry]
            }.merge(optional)
          end
        end
      end
    end
  end
end
