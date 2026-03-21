# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderBuilder
          # Typed reader builder inputs resolved directly from the container and launch state.
          ResolvedDependencies = Data.define(
            :reader_launch_state,
            :document,
            :worker,
            :input_system_factory,
            :terminal_service,
            :terminal_session,
            :page_calculator,
            :clipboard_service,
            :layout_service,
            :rendering_factory,
            :dictionary_ui_session,
            :in_book_search_ui_session,
            :annotation_overlay_ui_session,
            :annotation_editor_launcher,
            :app_config_store,
            :reader_state_reader,
            :reader_session_store,
            :reader_view_state_store,
            :reader_pagination_store,
            :reader_session_mutator,
            :reader_runtime_context,
            :reader_ui_session_registry,
            :clock,
            :observer_registry,
            :instrumentation,
            :navigation_service,
            :bookmark_service,
            :key_classifier,
            :selection_service,
            :wrapping_service,
            :rendered_content_reader,
            :annotation_service,
            :render_registry,
            :document_loader,
            :coordinate_service,
            :reader_document_locator,
            :popup_position_service,
            :notification_service,
            :ui_component_factory,
            :layout_metrics,
            :translation_service,
            :dictionary_service,
            :dictionary_catalog_service,
            :settings_service,
            :dictionary_availability,
            :dictionary_storage,
            :runtime_config,
            :formatting_service,
            :background_worker_builder,
            :progress_repository,
            :bookmark_repository,
            :pagination_cache,
            :notification_writer,
            :async_executor,
            :display_capabilities,
            :process_control,
            :instrumentation_service,
            :pagination_cache_preloader,
            :render_state_writer,
            :logger,
            :view_model_builder_factory,
            :kitty_image_renderer,
            :image_cache_warmup
          ) do
            def self.resolve(container:, preloaded_document:, background_worker:)
              launch_state = container.resolve(:reader_launch_state)

              new(
                reader_launch_state: launch_state,
                document: preloaded_document || launch_state&.preloaded_document,
                worker: background_worker || launch_state&.background_worker,
                **container_fields.to_h { |field| [field, container.resolve(field)] }
              )
            end

            def self.container_fields
              members - %i[reader_launch_state document worker]
            end
            private_class_method :container_fields
          end
        end
      end
    end
  end
end
