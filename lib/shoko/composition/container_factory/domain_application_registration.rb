# frozen_string_literal: true

require_relative '../../adapters/ui/theme_context'
require_relative '../../shared/hash_normalizer'

module Shoko
  module Composition
    module ContainerFactory
      # Registers domain and application services in the DI container.
      # Flat by design: composition wiring kept in one readable place rather than a
      # tree of single-use mixins (see constitution §IV).
      module DomainApplicationRegistration
        # Register application-level services and adapters.
        def register_application_services(container)
          register_output_services(container)
          register_use_case_services(container)
          register_document_loader(container)
        end

        def register_domain_services(container)
          register_domain_event_factory(container)
          register_reader_domain_services(container)
          register_annotation_services(container)
          register_dictionary_services(container)
          register_translation_services(container)
        end

        def register_output_services(container)
          register_terminal_output_services(container)
          register_formatting_output_services(container)
          register_resource_output_services(container)
          register_runtime_output_services(container)
          register_ui_output_services(container)
        end

        def register_use_case_services(container)
          register_catalog_service(container)
          register_download_service(container)
          register_settings_service(container)
          register_pagination_cache_preloader(container)
          register_prepagination_progress_writer(container)
          register_library_prepagination_warmup(container)
        end

        def register_prepagination_progress_writer(container)
          container.register_singleton(:prepagination_progress_writer) do |c|
            require_relative '../../adapters/runtime/session_state/prepagination_progress_writer_adapter'

            Shoko::Adapters::Runtime::SessionState::PrepaginationProgressWriterAdapter.new(c.resolve(:global_state))
          end
        end

        # The warmup only supervises: the pagination itself runs in a separate
        # low-priority OS process (see PrepaginationBatchProcessAdapter), so the
        # menu's render loop never competes with page-map builds for the GIL.
        def register_library_prepagination_warmup(container)
          register_prepagination_batch_runner(container)
          container.register_singleton(:library_prepagination_warmup) do |c|
            require_relative '../../application/workflows/menu/library_prepagination_warmup'

            Shoko::Application::Workflows::Menu::LibraryPrepaginationWarmup.new(
              deps: Shoko::Application::Workflows::Menu::LibraryPrepaginationWarmup::Dependencies.new(
                batch_runner: c.resolve(:prepagination_batch_runner),
                app_config_store: c.resolve(:app_config_store),
                reader_runtime_context: c.resolve(:reader_runtime_context),
                progress_writer: c.resolve(:prepagination_progress_writer),
                background_worker_builder: c.resolve(:background_worker_builder),
                logger: c.resolve(:logger)
              )
            )
          end
        end

        def register_prepagination_batch_runner(container)
          container.register_singleton(:prepagination_batch_runner) do |c|
            require_relative '../../adapters/runtime/prepagination_batch_process_adapter'

            Shoko::Adapters::Runtime::PrepaginationBatchProcessAdapter.new(logger: c.resolve(:logger))
          end
        end

        # Build a lambda that resolves the correct content parser for a chapter
        # based on its metadata[:format] hint. Falls back to the XHTML parser.
        def build_format_parser_resolver(xhtml_factory, logger)
          lambda do |raw, chapter|
            metadata = Shoko::Shared::HashNormalizer.symbolize_keys(chapter&.metadata) || {}
            format = metadata[:format]

            format_key = format.to_s.strip.downcase
            if !format_key.empty? && format_key != 'epub'
              factory = Shoko::Adapters::BookSources::FormatRegistry.content_parser_factory_for("dummy.#{format_key}")
              parser = factory&.call(raw, logger: logger)
              return parser if parser
            end

            xhtml_factory.call(raw)
          end
        end

        def register_document_loader(container)
          container.register_singleton(:document_loader) do |c|
            require_relative '../../application/services/book_document_loader'

            Shoko::Application::Services::BookDocumentLoader.new(
              book_cache_store: c.resolve(:book_cache_store),
              book_importer_resolver: c.resolve(:book_importer_resolver),
              book_resource_warmup: c.resolve(:image_cache_warmup),
              runtime_config: c.resolve(:runtime_config),
              logger: c.resolve(:logger)
            )
          end
        end

        private

        def register_domain_event_factory(container)
          container.register_singleton(:domain_event_factory) do |c|
            Shoko::Core::Events::EventFactory.new(
              wall_clock: c.resolve(:wall_clock),
              id_generator: c.resolve(:id_generator)
            )
          end
        end

        def register_reader_domain_services(container)
          register_navigation_service(container)
          register_bookmark_service(container)
          register_page_calculator(container)
          register_coordinate_service(container)
          register_reader_document_locator(container)
          register_popup_position_service(container)
          register_selection_service(container)
          register_layout_service(container)
          register_chapter_cache_factory(container)
        end

        def register_navigation_service(container)
          container.register_factory(:navigation_service) do |c|
            require_relative '../../application/services/reader/navigation_service'

            Shoko::Application::Services::Reader::NavigationService.new(
              app_config_store: c.resolve(:app_config_store),
              reader_session_store: c.resolve(:reader_session_store),
              reader_state_reader: lazy_container_service(c, :reader_state_reader),
              reader_runtime_context: c.resolve(:reader_runtime_context),
              page_calculator: c.resolve(:page_calculator),
              layout_service: c.resolve(:layout_service),
              wrapped_lines_provider: c.resolve(:wrapped_lines_provider),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_bookmark_service(container)
          container.register_factory(:bookmark_service) do |c|
            require_relative '../../application/services/reader/bookmark_service'

            Shoko::Application::Services::Reader::BookmarkService.new(
              bookmark_repository: c.resolve(:bookmark_repository),
              domain_event_bus: c.resolve(:domain_event_bus),
              domain_event_factory: c.resolve(:domain_event_factory),
              app_config_store: c.resolve(:app_config_store),
              reader_session_store: c.resolve(:reader_session_store),
              reader_state_reader: lazy_container_service(c, :reader_state_reader),
              reader_runtime_context: c.resolve(:reader_runtime_context),
              page_calculator: c.resolve(:page_calculator),
              layout_service: c.resolve(:layout_service),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_page_calculator(container)
          container.register_singleton(:page_calculator) do |c|
            require_relative '../../application/services/pagination/page_calculator_service'

            Shoko::Application::Services::Pagination::PageCalculatorService.new(**page_calculator_dependencies(c))
          end
        end

        def register_coordinate_service(container)
          container.register_factory(:coordinate_service) do |c|
            require_relative '../../application/services/coordinate_service'

            Shoko::Application::Services::CoordinateService.new(logger: c.resolve(:logger))
          end
        end

        def register_reader_document_locator(container)
          container.register_factory(:reader_document_locator) do |c|
            require_relative '../../adapters/storage/reader_document_locator'

            Shoko::Adapters::Storage::ReaderDocumentLocator.new(
              cache_pointer_resolver: c.resolve(:cache_pointer_resolver),
              path_ops: c.resolve(:path_ops),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_popup_position_service(container)
          container.register_factory(:popup_position_service) do |c|
            require_relative '../../application/services/popup_position_service'

            Shoko::Application::Services::PopupPositionService.new(
              reader_runtime_context: c.resolve(:reader_runtime_context)
            )
          end
        end

        def register_selection_service(container)
          container.register_factory(:selection_service) do |c|
            require_relative '../../application/services/selection_service'

            Shoko::Application::Services::SelectionService.new(
              coordinate_service: c.resolve(:coordinate_service),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_layout_service(container)
          container.register_factory(:layout_service) do |_c|
            require_relative '../../application/services/layout_service'

            Shoko::Application::Services::LayoutService.new
          end
        end

        def register_chapter_cache_factory(container)
          container.register_singleton(:chapter_cache_factory) do |_c|
            lambda do |text_metrics:|
              require_relative '../../core/services/pagination/internal/chapter_cache'

              Shoko::Core::Services::Pagination::Internal::ChapterCache.new(text_metrics: text_metrics)
            end
          end
        end

        def register_annotation_services(container)
          register_core_annotation_service(container)
          register_reader_annotation_service(container)
        end

        def register_dictionary_services(container)
          register_dictionary_lookup_service(container)
          register_dictionary_repository_service(container)
        end

        def register_translation_services(container)
          container.register_factory(:translation_service) do |c|
            require_relative '../../core/services/translation_service'

            Shoko::Core::Services::TranslationService.new(
              translation_repository: c.resolve(:translation_repository),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_dictionary_lookup_service(container)
          container.register_factory(:dictionary_service) do |c|
            require_relative '../../core/services/dictionary_service'

            Shoko::Core::Services::DictionaryService.new(
              dictionary_repository: c.resolve(:dictionary_repository),
              config_reader: c.resolve(:app_config_store),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_dictionary_repository_service(container)
          container.register_factory(:dictionary_repository) do |c|
            build_dictionary_repository(c)
          end
        end

        def build_dictionary_repository(container)
          require_relative '../../adapters/storage/sqlite_dictionary_adapter'

          config_reader = container.resolve(:app_config_store)
          runtime_config = container.resolve(:runtime_config)
          backend_name = config_reader&.dictionary_backend.to_s.downcase
          runtime_override = runtime_config&.dictionary_backend_override
          return nil unless dictionary_backend_enabled?(backend_name: backend_name, runtime_override: runtime_override)

          dict_path = config_reader&.dictionary_path
          Shoko::Adapters::Storage::SqliteDictionaryAdapter.new(
            databases_path: dict_path,
            logger: container.resolve(:logger)
          )
        end

        def dictionary_backend_enabled?(backend_name:, runtime_override:)
          backend_name != 'disabled' && runtime_override != 'disabled'
        end

        def page_calculator_dependencies(container)
          {
            text_metrics: container.resolve(:text_metrics),
            display_capabilities: container.resolve(:display_capabilities),
            instrumentation: container.resolve(:instrumentation),
            config_reader: container.resolve(:app_config_store),
            layout_service: container.resolve(:layout_service),
            pagination_cache: container.resolve(:pagination_cache),
            wrapping_service: container.resolve(:wrapping_service),
            formatting_service: container.resolve(:formatting_service),
            logger: container.resolve(:logger),
          }
        end

        def register_core_annotation_service(container)
          container.register_factory(:core_annotation_service) do |c|
            require_relative '../../core/services/annotation_service'

            Shoko::Core::Services::AnnotationService.new(
              annotation_repository: c.resolve(:annotation_repository),
              domain_event_bus: c.resolve(:domain_event_bus),
              domain_event_factory: c.resolve(:domain_event_factory),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_reader_annotation_service(container)
          container.register_factory(:annotation_service) do |c|
            require_relative '../../application/services/reader/annotation_state_service'

            Shoko::Application::Services::Reader::AnnotationStateService.new(
              core_annotation_service: c.resolve(:core_annotation_service),
              reader_session_store: c.resolve(:reader_session_store),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_terminal_output_services(container)
          register_clipboard_service(container)
          register_terminal_service(container)
          register_terminal_session(container)
          register_cli_progress_renderer(container)
        end

        def register_clipboard_service(container)
          container.register_factory(:clipboard_service) do |c|
            Shoko::Adapters::Output::Clipboard::ClipboardService.new(logger: c.resolve(:logger))
          end
        end

        def register_terminal_service(container)
          container.register_singleton(:terminal_service) do |c|
            Shoko::Adapters::Output::Terminal::TerminalService.new(
              runtime_config: c.resolve(:runtime_config),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_terminal_session(container)
          container.register_singleton(:terminal_session) do |c|
            Shoko::Adapters::Output::Terminal::TerminalSessionAdapter.new(
              terminal_service: c.resolve(:terminal_service)
            )
          end
        end

        def register_cli_progress_renderer(container)
          container.register_factory(:cli_progress_renderer) do |c|
            Shoko::Adapters::Output::Terminal::CLIProgressRenderer.new(
              terminal_service: c.resolve(:terminal_service)
            )
          end
        end

        def register_formatting_output_services(container)
          register_wrapping_service(container)
          register_formatting_service(container)
        end

        def register_wrapping_service(container)
          container.register_singleton(:wrapping_service) do |c|
            require_relative '../../adapters/output/formatting/wrapping_service'

            Shoko::Adapters::Output::Formatting::WrappingService.new(
              text_metrics: c.resolve(:text_metrics),
              async_executor: c.resolve(:async_executor),
              config_reader: c.resolve(:app_config_store),
              runtime_config: c.resolve(:runtime_config),
              formatting_service: c.resolve(:formatting_service),
              chapter_cache_factory: c.resolve(:chapter_cache_factory),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_formatting_service(container)
          container.register_singleton(:formatting_service) do |c|
            require_relative '../../adapters/output/formatting/formatting_service'

            xhtml_factory = c.resolve(:xhtml_parser_factory)
            logger = c.resolve(:logger)
            Shoko::Adapters::Output::Formatting::FormattingService.new(
              xhtml_parser_factory: xhtml_factory,
              format_parser_resolver: build_format_parser_resolver(xhtml_factory, logger),
              runtime_config: c.resolve(:runtime_config),
              logger: logger
            )
          end
        end

        def register_resource_output_services(container)
          register_epub_resource_loader(container)
          register_kitty_image_renderer(container)
          register_image_cache_warmup(container)
        end

        def register_epub_resource_loader(container)
          container.register_singleton(:epub_resource_loader) do |c|
            require_relative '../../adapters/book_sources/epub/epub_resource_loader'

            Shoko::Adapters::BookSources::Epub::EpubResourceLoader.new(
              cache_root: c.resolve(:cache_paths).cache_root,
              file_writer: c.resolve(:atomic_file_writer),
              runtime_config: c.resolve(:runtime_config),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_kitty_image_renderer(container)
          container.register_singleton(:kitty_image_renderer) do |c|
            require_relative '../../adapters/output/kitty/kitty_image_renderer'

            loader = Shoko::Adapters::Output::Kitty::ResourceLoader.new(loader: c.resolve(:epub_resource_loader))
            Shoko::Adapters::Output::Kitty::KittyImageRenderer.new(resource_loader: loader)
          end
        end

        def register_image_cache_warmup(container)
          container.register_singleton(:image_cache_warmup) do |c|
            require_relative '../../adapters/output/kitty/image_cache_warmup'

            Shoko::Adapters::Output::Kitty::ImageCacheWarmup.new(
              kitty_image_renderer: c.resolve(:kitty_image_renderer),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_runtime_output_services(container)
          register_wrapped_lines_provider(container)
          register_file_writer(container)
          register_instrumentation_service(container)
          register_notification_service(container)
        end

        def register_wrapped_lines_provider(container)
          container.register_singleton(:wrapped_lines_provider) do |c|
            Shoko::Adapters::Runtime::SessionState::WrappedLinesProviderAdapter.new(
              formatting_service: c.resolve(:formatting_service),
              launch_state: c.resolve(:reader_launch_state)
            )
          end
        end

        def register_file_writer(container)
          container.register_singleton(:file_writer) do |c|
            require_relative '../../adapters/storage/file_writer_service'

            Shoko::Adapters::Storage::FileWriterService.new(
              atomic_file_writer: c.resolve(:atomic_file_writer),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_instrumentation_service(container)
          container.register_singleton(:instrumentation_service) do |c|
            Shoko::Adapters::Output::InstrumentationService.new(
              performance_monitor: c.resolve(:performance_monitor),
              perf_tracer: c.resolve(:perf_tracer),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_notification_service(container)
          container.register_singleton(:notification_service) do |c|
            Shoko::Adapters::Output::NotificationService.new(
              logger: c.resolve(:logger),
              notification_writer: c.resolve(:notification_writer)
            )
          end
        end

        def register_ui_output_services(container)
          container.register_singleton(:ui_component_factory) do |c|
            build_ui_component_factory(c)
          end

          container.register_singleton(:render_registry) { |_c| Shoko::Adapters::Ui::RenderRegistry.new }

          container.register_factory(:dictionary_catalog_service) do |c|
            require_relative '../../adapters/storage/dictionary_catalog_service'

            Shoko::Adapters::Storage::DictionaryCatalogService.new(logger: c.resolve(:logger))
          end
        end

        def build_ui_component_factory(container)
          config_reader = container.resolve(:app_config_store)
          fallback_mode = Shoko::Adapters::Output::Terminal::Terminal.color_mode
          theme_context = Shoko::Adapters::Ui::ThemeContext.apply!(
            theme_id: config_reader&.theme,
            fallback_color_mode: fallback_mode
          )
          Shoko::Adapters::Ui::ComponentFactory.new(
            config_reader: config_reader,
            fallback_color_mode: theme_context.color_mode
          )
        end

        def register_catalog_service(container)
          container.register_factory(:catalog_service) do |c|
            Shoko::Application::UseCases::CatalogService.new(
              library_scanner: c.resolve(:library_scanner),
              metadata_reader: c.resolve(:metadata_reader),
              cached_library_repository: c.resolve(:cached_library_repository),
              display_metadata_cache: c.resolve(:display_metadata_cache),
              background_worker_builder: c.resolve(:background_worker_builder),
              recent_files_repository: c.resolve(:recent_files_repository),
              logger: c.resolve(:logger),
              file_probe: c.resolve(:file_probe)
            )
          end
        end

        def register_download_service(container)
          container.register_factory(:download_service) do |c|
            require_relative '../../adapters/book_sources/download_service'

            config_storage = c.resolve(:config_storage)
            downloads = config_storage ? File.join(config_storage.config_dir, 'downloads') : nil
            Shoko::Adapters::BookSources::DownloadService.new(
              gutendex_client: c.resolve(:gutendex_client),
              libgen_client: c.resolve(:libgen_client),
              downloads_root: downloads,
              logger: c.resolve(:logger)
            )
          end
        end

        def register_settings_service(container)
          container.register_factory(:settings_service) do |c|
            require_relative '../../application/use_cases/settings_service'

            Shoko::Application::UseCases::SettingsService.new(**settings_service_dependencies(c))
          end
        end

        def settings_service_dependencies(container)
          {
            app_config_store: container.resolve(:app_config_store),
            cache_manager: container.resolve(:cache_manager),
            dictionary_availability: container.resolve(:dictionary_availability),
            dictionary_storage: container.resolve(:dictionary_storage),
            data_cleanup: container.resolve(:data_cleanup),
            wrapping_service: container.resolve(:wrapping_service),
            recent_files_repository: container.resolve(:recent_files_repository),
            dictionary_service: container.resolve(:dictionary_service),
            catalog_service: container.resolve(:catalog_service),
            config_storage: container.resolve(:config_storage),
            logger: container.resolve(:logger),
          }
        end

        def register_pagination_cache_preloader(container)
          container.register_factory(:pagination_cache_preloader) do |c|
            require_relative '../../application/services/pagination/pagination_cache_preloader'

            Shoko::Application::Services::Pagination::PaginationCachePreloader.new(
              page_calculator: c.resolve(:page_calculator),
              pagination_cache: c.resolve(:pagination_cache),
              app_config_store: c.resolve(:app_config_store),
              reader_session_store: c.resolve(:reader_session_store),
              reader_state_reader: c.resolve(:reader_state_reader),
              reader_pagination_store: c.resolve(:reader_pagination_store),
              reader_runtime_context: c.resolve(:reader_runtime_context),
              logger: c.resolve(:logger)
            )
          end
        end
      end
    end
  end
end
