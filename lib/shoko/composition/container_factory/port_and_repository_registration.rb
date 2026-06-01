# frozen_string_literal: true

require_relative '../../adapters/output/terminal/text_metrics_port_adapter'
require_relative '../../adapters/output/kitty/display_capabilities'
require_relative '../../adapters/output/terminal_capabilities_adapter'
require_relative '../../adapters/output/layout/layout_metrics_adapter'
require_relative '../../adapters/input/key_classifier_adapter'
require_relative '../../adapters/output/terminal/text_sanitizer_adapter'
require_relative '../../adapters/runtime/inline_executor_adapter'
require_relative '../../adapters/storage/config_storage_adapter'
require_relative '../../adapters/storage/atomic_file_writer'
require_relative '../../adapters/book_sources/book_finder'
require_relative '../../adapters/book_sources/book_file_probe'
require_relative '../../adapters/book_sources/folder_scanner'
require_relative '../../adapters/book_sources/format_registry'
require_relative '../../adapters/book_sources/book_importer_resolver_adapter'
require_relative '../../adapters/book_sources/metadata_reader_adapter'
require_relative '../format_registry_composition'
require_relative '../../adapters/storage/dictionary_availability_adapter'
require_relative '../../adapters/storage/dictionary_storage_adapter'
require_relative '../../adapters/translation/libre_translate_adapter'
require_relative '../../adapters/storage/data_cleanup_adapter'
require_relative '../../adapters/storage/cache_manager_adapter'
require_relative '../../adapters/storage/cache_paths'
require_relative '../../adapters/storage/book_cache_store_adapter'
require_relative '../../adapters/storage/file_probe_adapter'
require_relative '../../adapters/storage/path_ops_adapter'
require_relative '../../adapters/book_sources/archive/zip_reader'
require_relative '../../adapters/input/input_system_factory_adapter'
require_relative '../../adapters/ui/rendering_factory'
require_relative '../../adapters/storage/repositories/bookmark_repository'
require_relative '../../adapters/storage/repositories/annotation_repository'
require_relative '../../adapters/storage/repositories/progress_repository'
require_relative '../../adapters/runtime/session_state/session_schema_reset_guard'
require_relative '../../application/state/observer_state_store'
require_relative '../../application/state/schema_registry'
require_relative '../../core/reading/schema'
require_relative '../../application/state/schema/reader_process'
require_relative '../../application/state/schema/reader_pagination'
require_relative '../../application/state/schema/reader_view'
require_relative '../../application/state/schema/menu_process'
require_relative '../../application/state/schema/menu_transient'
require_relative '../../application/state/schema/config'
require_relative '../../application/state/schema/ui_globals'
require_relative '../../adapters/runtime/session_state/app_config_store_adapter'
require_relative '../../adapters/ui/state/reader_component_registry'
require_relative '../../adapters/runtime/session_state/reader_session_store_adapter'
require_relative '../../adapters/runtime/session_state/reader_view_state_store_adapter'
require_relative '../../adapters/runtime/session_state/reader_pagination_store_adapter'
require_relative '../../adapters/runtime/session_state/reader_snapshot_projection_adapter'
require_relative '../../adapters/runtime/session_state/reader_runtime_context_adapter'
require_relative '../../adapters/runtime/session_state/reader_session_mutator'
require_relative '../../adapters/runtime/session_state/menu_session_store_adapter'
require_relative '../../adapters/runtime/session_state/menu_transient_store_adapter'
require_relative '../../adapters/runtime/session_state/menu_snapshot_projection_adapter'
require_relative '../../adapters/runtime/session_state/menu_session_mutator'
require_relative '../../adapters/runtime/session_state/rendered_content_reader_adapter'
require_relative '../../adapters/ui/sessions/dictionary_ui_session_adapter'
require_relative '../../adapters/ui/sessions/in_book_search_ui_session_adapter'
require_relative '../../adapters/ui/sessions/annotation_overlay_ui_session_adapter'
require_relative '../../adapters/ui/sessions/annotation_editor_launcher_adapter'
require_relative '../../adapters/runtime/session_state/observer_registry_adapter'
require_relative '../../adapters/runtime/session_state/render_state_writer_adapter'
require_relative '../../adapters/runtime/session_state/notification_writer_adapter'
require_relative '../../adapters/ui/view_models/reader_view_model_builder'
require_relative '../../adapters/storage/json_cache_store'
require_relative '../../adapters/storage/epub_cache'
require_relative '../../adapters/storage/cache_pointer_manager'
require_relative '../../adapters/storage/repositories/cached_library_repository'
require_relative '../../adapters/storage/repositories/display_metadata_cache_repository'
require_relative '../../adapters/book_sources/library_scanner'

module Shoko
  module Composition
    module ContainerFactory
      # Registers ports, adapters, and repositories in the DI container.
      # Flat by design: composition wiring is not domain logic and is kept in one
      # readable place rather than a tree of single-use mixins (see constitution §IV).
      module PortAndRepositoryRegistration
        # Registers the shared adapter ports used across runtime composition.
        def register_core_ports(container)
          register_terminal_ports(container)
          register_book_source_ports(container)
          register_dictionary_ports(container)
          register_translation_ports(container)
          register_storage_ports(container)
          register_archive_ports(container)
          register_ui_factory_ports(container)
        end


        def register_repositories(container)
          register_bookmark_repository(container)
          register_annotation_repository(container)
          register_progress_repository(container)
        end


        def register_state_management(container, event_bus)
          register_schema_registry(container)
          register_global_state(container, event_bus)
          container.register_factory(:state_store) { |c| c.resolve(:global_state) }
          register_hexagonal_adapters(container)
        end

        def register_hexagonal_adapters(container)
          register_reader_state_adapters(container)
          register_menu_state_adapters(container)
          register_reader_ui_adapters(container)
          register_render_state_adapters(container)
        end


        def register_library_services(container)
          register_library_cache_types(container)
          register_cached_library_repository(container)
          register_display_metadata_cache(container)
          register_library_scanner(container)
        end


        private

        def register_terminal_ports(container)
          register_display_ports(container)
          register_terminal_runtime_ports(container)
          register_input_classification_ports(container)
        end

        def register_display_ports(container)
          container.register_singleton(:text_metrics) do |c|
            Shoko::Adapters::Output::Terminal::TextMetricsPortAdapter.new(runtime_config: c.resolve(:runtime_config))
          end
          container.register_singleton(:display_capabilities) do |_c|
            Shoko::Adapters::Output::Kitty::DisplayCapabilities.new
          end
          container.register_singleton(:instrumentation) { |c| c.resolve(:instrumentation_service) }
        end

        def register_terminal_runtime_ports(container)
          container.register_factory(:async_executor) do |c|
            executor = c.resolve(:background_worker) if c.registered?(:background_worker)
            executor || Shoko::Adapters::Runtime::InlineExecutorAdapter.new
          rescue Shoko::Error
            Shoko::Adapters::Runtime::InlineExecutorAdapter.new
          end
          container.register_singleton(:terminal_capabilities) do |_c|
            Shoko::Adapters::Output::TerminalCapabilitiesAdapter.new
          end
          container.register_singleton(:layout_metrics) do |c|
            Shoko::Adapters::Output::Layout::LayoutMetricsAdapter.new(layout_service: c.resolve(:layout_service))
          end
        end

        def register_input_classification_ports(container)
          container.register_singleton(:key_classifier) do |_c|
            Shoko::Adapters::Input::KeyClassifierAdapter.new
          end
          container.register_singleton(:text_sanitizer) do |_c|
            Shoko::Adapters::Output::Terminal::TextSanitizerAdapter.new
          end
        end


        def register_book_source_ports(container)
          Shoko::Composition::FormatRegistryComposition.register!
          register_book_discovery_ports(container)
          register_metadata_ports(container)
          register_import_ports(container)
        end

        def register_book_discovery_ports(container)
          register_config_storage_ports(container)
          register_book_finder_port(container)
          register_folder_scanner_port(container)
        end

        def register_config_storage_ports(container)
          container.register_singleton(:config_storage) do |_c|
            Shoko::Adapters::Storage::ConfigStorageAdapter.new
          end
          container.register_singleton(:book_file_probe) do |_c|
            Shoko::Adapters::BookSources::BookFileProbe.new
          end
        end

        def register_book_finder_port(container)
          container.register_singleton(:book_finder) do |c|
            config_storage = c.resolve(:config_storage)
            Shoko::Adapters::BookSources::BookFinder.new(
              config_root: config_storage.config_dir,
              cache_writer: Shoko::Adapters::Storage::AtomicFileWriter,
              book_file_probe: c.resolve(:book_file_probe),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_folder_scanner_port(container)
          container.register_singleton(:folder_scanner) do |c|
            Shoko::Adapters::BookSources::FolderScanner.new(
              format_registry: Shoko::Adapters::BookSources::FormatRegistry,
              book_file_probe: c.resolve(:book_file_probe)
            )
          end
        end

        def register_metadata_ports(container)
          container.register_singleton(:metadata_reader) do |c|
            Shoko::Adapters::BookSources::MetadataReaderAdapter.new(
              file_probe: c.resolve(:file_probe),
              path_ops: c.resolve(:path_ops),
              file_reader: c.resolve(:binary_file_reader),
              text_reader: c.resolve(:utf8_file_reader),
              zip_open: c.resolve(:zip_open),
              zip_entry_reader: c.resolve(:zip_entry_reader)
            )
          end
        end

        def register_import_ports(container)
          container.register_singleton(:book_importer_resolver) do |_c|
            Shoko::Adapters::BookSources::BookImporterResolverAdapter.new(
              format_registry: Shoko::Adapters::BookSources::FormatRegistry
            )
          end
        end


        def register_dictionary_ports(container)
          container.register_singleton(:dictionary_availability) do |_c|
            require_relative '../../adapters/storage/sqlite_dictionary_adapter'

            Shoko::Adapters::Storage::DictionaryAvailabilityAdapter.new(
              backend_class: Shoko::Adapters::Storage::SqliteDictionaryAdapter
            )
          end
          container.register_singleton(:dictionary_storage) do |_c|
            Shoko::Adapters::Storage::DictionaryStorageAdapter.new
          end
        end

        def register_translation_ports(container)
          container.register_singleton(:translation_repository) do |c|
            Shoko::Adapters::Translation::LibreTranslateAdapter.new(logger: c.resolve(:logger))
          end
        end


        def register_storage_ports(container)
          register_cleanup_ports(container)
          register_book_cache_ports(container)
          register_file_system_ports(container)
        end

        def register_cleanup_ports(container)
          container.register_singleton(:data_cleanup) do |_c|
            Shoko::Adapters::Storage::DataCleanupAdapter.new
          end
          container.register_singleton(:cache_manager) do |c|
            Shoko::Adapters::Storage::CacheManagerAdapter.new(
              epub_cache_clearer: -> { c.resolve(:book_finder).clear_cache },
              cache_path_provider: Shoko::Adapters::Storage::CachePaths
            )
          end
        end

        def register_file_system_ports(container)
          container.register_singleton(:file_probe) do |_c|
            Shoko::Adapters::Storage::FileProbeAdapter.new
          end
          container.register_singleton(:path_ops) do |_c|
            Shoko::Adapters::Storage::PathOpsAdapter.new
          end
        end

        def register_book_cache_ports(container)
          container.register_singleton(:book_cache_store) do |c|
            Shoko::Adapters::Storage::BookCacheStoreAdapter.new(
              cache_root: c.resolve(:cache_paths).cache_root,
              runtime_config: c.resolve(:runtime_config),
              logger: c.resolve(:logger)
            )
          end
        end


        def register_archive_ports(container)
          register_archive_readers(container)
          register_zip_ports(container)
        end

        def register_archive_readers(container)
          container.register_singleton(:archive_reader) do |_c|
            Shoko::Adapters::BookSources::Archive::ZipReader
          end
          container.register_singleton(:binary_file_reader) do |_c|
            ->(path) { File.binread(path) }
          end
          container.register_singleton(:utf8_file_reader) do |_c|
            ->(path) { File.read(path, encoding: 'UTF-8') }
          end
        end

        def register_zip_ports(container)
          register_zip_open_port(container)
          register_zip_entry_reader_port(container)
        end

        def register_zip_open_port(container)
          container.register_singleton(:zip_open) do |c|
            archive_reader = c.resolve(:archive_reader)
            runtime_config = c.resolve(:runtime_config)
            lambda do |path, &block|
              archive_reader.open(path, runtime_config: runtime_config, &block)
            end
          end
        end

        def register_zip_entry_reader_port(container)
          container.register_singleton(:zip_entry_reader) do |c|
            archive_reader = c.resolve(:archive_reader)
            runtime_config = c.resolve(:runtime_config)
            build_zip_entry_reader(archive_reader, runtime_config)
          end
        end

        def build_zip_entry_reader(archive_reader, runtime_config)
          lambda do |path, suffix|
            archive_reader.open(path, runtime_config: runtime_config) do |zip|
              entry = zip.entries.find { |item| item.name.downcase.end_with?(suffix.to_s.downcase) }
              entry ? zip.read(entry.name) : nil
            end
          end
        end


        def register_ui_factory_ports(container)
          container.register_singleton(:input_system_factory) do |_c|
            Shoko::Adapters::Input::InputSystemFactoryAdapter.new
          end
          container.register_singleton(:rendering_factory) do |_c|
            Shoko::Adapters::Ui::RenderingFactory.new
          end
        end


        def register_bookmark_repository(container)
          container.register_factory(:bookmark_repository) do |c|
            Shoko::Adapters::Storage::Repositories::BookmarkRepository.new(
              file_writer: c.resolve(:file_writer),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_annotation_repository(container)
          container.register_factory(:annotation_repository) do |c|
            Shoko::Adapters::Storage::Repositories::AnnotationRepository.new(
              file_writer: c.resolve(:file_writer),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_progress_repository(container)
          container.register_factory(:progress_repository) do |c|
            Shoko::Adapters::Storage::Repositories::ProgressRepository.new(
              file_writer: c.resolve(:file_writer),
              logger: c.resolve(:logger)
            )
          end
        end


        def register_schema_registry(container)
          container.register_singleton(:schema_registry) do |_c|
            Shoko::Application::State::SchemaRegistry.new
              .register(Shoko::Core::Reading::Schema)
              .register(Shoko::Application::State::Schema::ReaderProcess)
              .register(Shoko::Application::State::Schema::ReaderPagination)
              .register(Shoko::Application::State::Schema::ReaderView)
              .register(Shoko::Application::State::Schema::MenuProcess)
              .register(Shoko::Application::State::Schema::MenuTransient)
              .register(Shoko::Application::State::Schema::Config)
              .register(Shoko::Application::State::Schema::UiGlobals)
          end
        end

        def register_global_state(container, event_bus)
          container.register_singleton(:global_state) do |c|
            Shoko::Adapters::Runtime::SessionState::SessionSchemaResetGuard.new(
              config_storage: c.resolve(:config_storage),
              cache_paths: c.resolve(:cache_paths),
              logger: c.resolve(:logger)
            ).ensure_current_schema!
            Shoko::Application::State::ObserverStateStore.new(
              event_bus,
              config_storage: c.resolve(:config_storage),
              terminal_capabilities: c.resolve(:terminal_capabilities),
              schema_registry: c.resolve(:schema_registry),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_reader_state_adapters(container)
          register_reader_store_adapters(container)
          register_reader_runtime_adapters(container)
        end

        def register_reader_store_adapters(container)
          container.register_factory(:app_config_store) do |c|
            Shoko::Adapters::Runtime::SessionState::AppConfigStoreAdapter.new(c.resolve(:global_state))
          end
          container.register_singleton(:reader_component_registry) do |_c|
            Shoko::Adapters::Ui::State::ReaderComponentRegistry.new
          end
          container.register_factory(:reader_session_store) do |c|
            Shoko::Adapters::Runtime::SessionState::ReaderSessionStoreAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:reader_view_state_store) do |c|
            Shoko::Adapters::Runtime::SessionState::ReaderViewStateStoreAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:reader_pagination_store) do |c|
            Shoko::Adapters::Runtime::SessionState::ReaderPaginationStoreAdapter.new(c.resolve(:global_state))
          end
        end

        def register_reader_runtime_adapters(container)
          register_reader_state_projection(container)
          register_reader_runtime_context_adapter(container)
          register_reader_session_mutator_adapter(container)
        end

        def register_reader_state_projection(container)
          container.register_factory(:reader_state_reader) do |c|
            Shoko::Adapters::Runtime::SessionState::ReaderSnapshotProjectionAdapter.new(
              state: c.resolve(:global_state),
              reader_session_store: c.resolve(:reader_session_store),
              reader_view_state_store: c.resolve(:reader_view_state_store),
              reader_pagination_store: c.resolve(:reader_pagination_store),
              component_registry: c.resolve(:reader_component_registry)
            )
          end
        end

        def register_reader_runtime_context_adapter(container)
          container.register_factory(:reader_runtime_context) do |c|
            Shoko::Adapters::Runtime::SessionState::ReaderRuntimeContextAdapter.new(
              terminal_session: c.resolve(:terminal_session),
              display_capabilities: c.resolve(:display_capabilities),
              app_config_store: c.resolve(:app_config_store),
              reader_view_state_store: c.resolve(:reader_view_state_store),
              reader_pagination_store: c.resolve(:reader_pagination_store)
            )
          end
        end

        def register_reader_session_mutator_adapter(container)
          container.register_factory(:reader_session_mutator) do |c|
            Shoko::Adapters::Runtime::SessionState::ReaderSessionMutator.new(
              reader_session_store: c.resolve(:reader_session_store),
              reader_view_state_store: c.resolve(:reader_view_state_store),
              reader_pagination_store: c.resolve(:reader_pagination_store),
              app_config_store: c.resolve(:app_config_store),
              component_registry: c.resolve(:reader_component_registry)
            )
          end
        end

        def register_menu_state_adapters(container)
          register_menu_store_adapters(container)
          register_menu_mutation_adapters(container)
        end

        def register_menu_store_adapters(container)
          container.register_factory(:menu_session_store) do |c|
            Shoko::Adapters::Runtime::SessionState::MenuSessionStoreAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:menu_transient_store) do |c|
            Shoko::Adapters::Runtime::SessionState::MenuTransientStoreAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:menu_snapshot_projection) do |c|
            Shoko::Adapters::Runtime::SessionState::MenuSnapshotProjectionAdapter.new(
              state: c.resolve(:global_state),
              menu_session_store: c.resolve(:menu_session_store),
              menu_transient_store: c.resolve(:menu_transient_store)
            )
          end
        end

        def register_menu_mutation_adapters(container)
          container.register_factory(:menu_session_mutator) do |c|
            Shoko::Adapters::Runtime::SessionState::MenuSessionMutator.new(
              menu_session_store: c.resolve(:menu_session_store),
              menu_transient_store: c.resolve(:menu_transient_store)
            )
          end
        end


        def register_reader_ui_adapters(container)
          register_rendered_content_adapter(container)
          register_overlay_ui_sessions(container)
          register_annotation_ui_adapters(container)
        end

        def register_rendered_content_adapter(container)
          container.register_factory(:rendered_content_reader) do |c|
            Shoko::Adapters::Runtime::SessionState::RenderedContentReaderAdapter.new(
              c.resolve(:global_state),
              render_registry: c.resolve(:render_registry)
            )
          end
        end

        def register_overlay_ui_sessions(container)
          register_dictionary_ui_session(container)
          register_in_book_search_ui_session(container)
        end

        def register_dictionary_ui_session(container)
          container.register_factory(:dictionary_ui_session) do |c|
            Shoko::Adapters::Ui::Sessions::DictionaryUiSessionAdapter.new(
              reader_state_reader: c.resolve(:reader_state_reader),
              reader_session_mutator: c.resolve(:reader_session_mutator),
              ui_component_factory: c.resolve(:ui_component_factory),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_in_book_search_ui_session(container)
          container.register_factory(:in_book_search_ui_session) do |c|
            Shoko::Adapters::Ui::Sessions::InBookSearchUiSessionAdapter.new(
              reader_state_reader: c.resolve(:reader_state_reader),
              reader_session_mutator: c.resolve(:reader_session_mutator),
              ui_component_factory: c.resolve(:ui_component_factory),
              rendered_content_reader: c.resolve(:rendered_content_reader),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_annotation_ui_adapters(container)
          register_annotation_overlay_ui_session(container)
          register_annotation_editor_launcher(container)
        end

        def register_annotation_overlay_ui_session(container)
          container.register_factory(:annotation_overlay_ui_session) do |c|
            Shoko::Adapters::Ui::Sessions::AnnotationOverlayUiSessionAdapter.new(
              reader_state_reader: c.resolve(:reader_state_reader),
              reader_session_mutator: c.resolve(:reader_session_mutator),
              ui_component_factory: c.resolve(:ui_component_factory),
              rendered_content_reader: c.resolve(:rendered_content_reader),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_annotation_editor_launcher(container)
          container.register_factory(:annotation_editor_launcher) do |c|
            Shoko::Adapters::Ui::Sessions::AnnotationEditorLauncherAdapter.new(
              annotation_overlay_ui_session: c.resolve(:annotation_overlay_ui_session)
            )
          end
        end

        def register_render_state_adapters(container)
          register_observer_render_adapters(container)
          register_view_model_builder_factory(container)
        end

        def register_observer_render_adapters(container)
          register_observer_registry(container)
          register_state_writers(container)
        end

        def register_observer_registry(container)
          container.register_factory(:observer_registry) do |c|
            Shoko::Adapters::Runtime::SessionState::ObserverRegistryAdapter.new(c.resolve(:global_state))
          end
        end

        def register_state_writers(container)
          container.register_factory(:render_state_writer) do |c|
            Shoko::Adapters::Runtime::SessionState::RenderStateWriterAdapter.new(
              c.resolve(:global_state),
              render_registry: c.resolve(:render_registry),
              logger: c.resolve(:logger)
            )
          end
          container.register_factory(:notification_writer) do |c|
            Shoko::Adapters::Runtime::SessionState::NotificationWriterAdapter.new(
              c.resolve(:global_state),
              text_sanitizer: c.resolve(:text_sanitizer)
            )
          end
        end

        def register_view_model_builder_factory(container)
          container.register_factory(:view_model_builder_factory) do |c|
            build_view_model_builder_factory(c)
          end
        end

        def build_view_model_builder_factory(container)
          reader_state_reader = container.resolve(:reader_state_reader)
          config_reader = container.resolve(:app_config_store)
          lambda do |doc|
            Shoko::Adapters::Ui::ViewModels::ReaderViewModelBuilder.new(
              reader_state_reader: reader_state_reader,
              config_reader: config_reader,
              doc: doc
            )
          end
        end


        def register_library_cache_types(container)
          container.register_singleton(:json_cache_store) do |c|
            Shoko::Adapters::Storage::JsonCacheStore.new(
              cache_root: c.resolve(:cache_paths).cache_root,
              runtime_config: c.resolve(:runtime_config)
            )
          end
          container.register(:json_cache_store_class, Shoko::Adapters::Storage::JsonCacheStore)
          container.register(:epub_cache_class, Shoko::Adapters::Storage::EpubCache)
          container.register(:cache_pointer_manager_class, Shoko::Adapters::Storage::CachePointerManager)
        end

        def register_cached_library_repository(container)
          container.register_singleton(:cached_library_repository) do |c|
            Shoko::Adapters::Storage::Repositories::CachedLibraryRepository.new(
              cache_root: c.resolve(:cache_paths).cache_root,
              store: c.resolve(:json_cache_store),
              runtime_config: c.resolve(:runtime_config),
              manifest_store: c.resolve(:json_cache_store_class),
              cache_class: c.resolve(:epub_cache_class),
              pointer_manager_class: c.resolve(:cache_pointer_manager_class)
            )
          end
        end

        def register_display_metadata_cache(container)
          container.register_singleton(:display_metadata_cache) do |c|
            Shoko::Adapters::Storage::Repositories::DisplayMetadataCacheRepository.new(
              cache_root: c.resolve(:cache_paths).cache_root,
              atomic_file_writer: c.resolve(:atomic_file_writer)
            )
          end
        end

        def register_library_scanner(container)
          container.register_factory(:library_scanner) do |c|
            Shoko::Adapters::BookSources::LibraryScanner.new(
              background_worker_builder: c.resolve(:background_worker_builder),
              logger: c.resolve(:logger),
              book_finder: c.resolve(:book_finder)
            )
          end
        end

      end
    end
  end
end
