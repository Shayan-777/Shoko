# frozen_string_literal: true

require_relative '../../../../adapters/ui/dependency_sets'
require_relative '../../../../shared/lazy_proxy'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module MenuBuilder
          EAGER_SERVICE_MAP = {
            rendering_factory: :rendering_factory,
            menu_launch_state: :menu_launch_state,
            terminal_service: :terminal_service,
            menu_session_store: :menu_session_store,
            menu_transient_store: :menu_transient_store,
            menu_state_reader: :menu_snapshot_projection,
            menu_session_mutator: :menu_session_mutator,
            app_config_store: :app_config_store,
            logger: :logger,
            catalog_service: :catalog_service,
            runtime_config: :runtime_config,
            file_probe: :file_probe,
            path_ops: :path_ops,
            clock: :clock,
            process_control: :process_control,
            observer_registry: :observer_registry,
            ui_component_factory: :ui_component_factory,
            key_classifier: :key_classifier,
            input_system_factory: :input_system_factory,
            notification_service: :notification_service,
            clipboard_service: :clipboard_service,
            pagination_cache: :pagination_cache,
            instrumentation: :instrumentation,
            text_sanitizer: :text_sanitizer,
          }.freeze

          LAZY_SERVICE_MAP = {
            reader_runtime_context: :reader_runtime_context,
            reader_state_reader: :reader_state_reader,
            dictionary_availability: :dictionary_availability,
            dictionary_storage: :dictionary_storage,
            annotation_service: :annotation_service,
            settings_service: :settings_service,
            translation_service: :translation_service,
            download_service: :download_service,
            dictionary_catalog_service: :dictionary_catalog_service,
            cache_pointer_resolver: :cache_pointer_resolver,
            reader_document_locator: :reader_document_locator,
            document_loader: :document_loader,
            background_worker_builder: :background_worker_builder,
            recent_files_repository: :recent_files_repository,
            page_calculator: :page_calculator,
            pagination_cache_preloader: :pagination_cache_preloader,
          }.freeze

          # Typed menu controller build inputs with lazily-resolved heavy collaborators.
          MenuBuildContext = Data.define(
            :rendering_factory,
            :reader_launch_state,
            :menu_launch_state,
            :terminal_service,
            :reader_runtime_context,
            :reader_session_store,
            :reader_view_state_store,
            :reader_pagination_store,
            :reader_state_reader,
            :menu_session_store,
            :menu_transient_store,
            :menu_state_reader,
            :menu_session_mutator,
            :app_config_store,
            :logger,
            :catalog_service,
            :dictionary_availability,
            :dictionary_storage,
            :annotation_service,
            :settings_service,
            :translation_service,
            :runtime_config,
            :file_probe,
            :path_ops,
            :clock,
            :process_control,
            :observer_registry,
            :ui_component_factory,
            :key_classifier,
            :input_system_factory,
            :notification_service,
            :clipboard_service,
            :pagination_cache,
            :instrumentation,
            :download_service,
            :dictionary_catalog_service,
            :text_sanitizer,
            :cache_pointer_resolver,
            :reader_document_locator,
            :document_loader,
            :background_worker_builder,
            :recent_files_repository,
            :page_calculator,
            :pagination_cache_preloader,
            :document
          ) do
            def self.resolve(container)
              reader_launch_state = container.resolve(:reader_launch_state)

              new(
                **resolve_services(container, EAGER_SERVICE_MAP),
                reader_launch_state: reader_launch_state,
                reader_session_store: container.resolve(:reader_session_store),
                reader_view_state_store: container.resolve(:reader_view_state_store),
                reader_pagination_store: container.resolve(:reader_pagination_store),
                **resolve_lazy_services(container, LAZY_SERVICE_MAP),
                document: reader_launch_state&.preloaded_document
              )
            end

            def menu_ui_dependencies
              Shoko::Adapters::Ui::MenuUiDependencies.new(
                menu_state_reader: menu_state_reader,
                menu_session_mutator: menu_session_mutator,
                reader_state_reader: reader_state_reader,
                sidebar_state_reader: reader_state_reader,
                config_reader: app_config_store,
                runtime_config: runtime_config,
                dictionary_availability: dictionary_availability,
                dictionary_storage: dictionary_storage,
                annotation_service: annotation_service,
                catalog_service: catalog_service,
                reader_launch_state: reader_launch_state,
                document: document
              )
            end

            def self.resolve_services(container, service_map)
              service_map.transform_values { |service| container.resolve(service) }
            end
            private_class_method :resolve_services

            def self.resolve_lazy_services(container, service_map)
              service_map.transform_values { |service| lazy_service(container, service) }
            end
            private_class_method :resolve_lazy_services

            def self.lazy_service(container, service_name)
              Shoko::Shared::LazyProxy.new { container.resolve(service_name) }
            end
            private_class_method :lazy_service
          end
        end
      end
    end
  end
end
