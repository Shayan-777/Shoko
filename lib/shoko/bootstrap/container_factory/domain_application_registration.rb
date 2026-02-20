# frozen_string_literal: true

module Shoko
  module Bootstrap
      module ContainerFactory
        # Registers domain and application services in the DI container.
        module DomainApplicationRegistration
          # Register core domain services
          def register_domain_services(container)
            container.register_factory(:navigation_service) do |c|
              Shoko::Application::Services::Reader::NavigationService.new(
                config_reader: c.resolve(:config_reader),
                reader_state_reader: c.resolve(:reader_navigation_reader),
                ui_state_reader: c.resolve(:ui_state_reader),
                state_writer: c.resolve(:reader_state_writer),
                page_calculator: c.resolve(:page_calculator),
                layout_service: c.resolve(:layout_service),
                wrapped_lines_provider: c.resolve_optional(:wrapped_lines_provider),
                display_capabilities: c.resolve_optional(:display_capabilities),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_factory(:bookmark_service) do |c|
              Shoko::Application::Services::Reader::BookmarkService.new(
                bookmark_repository: c.resolve(:bookmark_repository),
                domain_event_bus: c.resolve(:domain_event_bus),
                config_reader: c.resolve(:config_reader),
                reader_state_reader: c.resolve(:reader_navigation_reader),
                ui_state_reader: c.resolve(:ui_state_reader),
                state_writer: c.resolve(:reader_state_writer),
                page_calculator: c.resolve_optional(:page_calculator),
                layout_service: c.resolve_optional(:layout_service),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_singleton(:page_calculator) do |c|
              Shoko::Core::Services::PageCalculatorService.new(
                text_metrics: c.resolve(:text_metrics),
                display_capabilities: c.resolve(:display_capabilities),
                instrumentation: c.resolve(:instrumentation),
                config_reader: c.resolve(:config_reader),
                layout_service: c.resolve_optional(:layout_service),
                pagination_cache: c.resolve_optional(:pagination_cache),
                wrapping_service: c.resolve_optional(:wrapping_service),
                formatting_service: c.resolve_optional(:formatting_service),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_factory(:coordinate_service) do |c|
              Shoko::Core::Services::CoordinateService.new(
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_factory(:popup_position_service) do |c|
              Shoko::Application::Services::PopupPositionService.new(
                terminal_service: c.resolve(:terminal_service)
              )
            end
            container.register_factory(:selection_service) do |c|
              Shoko::Core::Services::SelectionService.new(
                coordinate_service: c.resolve(:coordinate_service),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_factory(:layout_service) do |_c|
              Shoko::Core::Services::LayoutService.new
            end
            container.register_factory(:core_annotation_service) do |c|
              Shoko::Core::Services::AnnotationService.new(
                annotation_repository: c.resolve(:annotation_repository),
                domain_event_bus: c.resolve(:domain_event_bus),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_factory(:annotation_service) do |c|
              Shoko::Application::Services::Reader::AnnotationStateService.new(
                core_annotation_service: c.resolve(:core_annotation_service),
                state_writer: c.resolve(:reader_state_writer),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_factory(:dictionary_service) do |c|
              Shoko::Core::Services::DictionaryService.new(
                dictionary_repository: c.resolve_optional(:dictionary_repository),
                config_reader: c.resolve_optional(:config_reader),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_factory(:dictionary_repository) do |c|
              config_reader = begin
                c.resolve(:config_reader)
              rescue StandardError
                nil
              end
              runtime_config = c.resolve_optional(:runtime_config)
              dictionary_availability = c.resolve(:dictionary_availability)
              backend = config_reader&.dictionary_backend
              backend_name = backend.to_s.downcase
              runtime_override = runtime_config&.dictionary_backend_override
              sqlite_available = dictionary_availability.sqlite3_available?
              enabled = if backend_name == 'disabled'
                          false
                        elsif runtime_override == 'disabled'
                          false
                        elsif runtime_override == 'sqlite'
                          true
                        elsif backend_name == 'sqlite'
                          true
                        else
                          sqlite_available
                        end

              next unless enabled
              next unless sqlite_available

              dict_path = config_reader&.dictionary_path
              Shoko::Adapters::Storage::SqliteDictionaryAdapter.new(databases_path: dict_path,
                                                                    logger: c.resolve_optional(:logger))
            end
          end

          # Register application-level services and adapters
          def register_application_services(container)
            register_output_services(container)
            register_use_case_services(container)
            register_document_factory(container)
          end

          # Register output/rendering services
          def register_output_services(container)
            container.register_factory(:clipboard_service) do |c|
              Shoko::Adapters::Output::Clipboard::ClipboardService.new(
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_singleton(:terminal_service) do |c|
              Shoko::Adapters::Output::Terminal::TerminalService.new(
                runtime_config: c.resolve_optional(:runtime_config),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_factory(:cli_progress_renderer) do |c|
              Shoko::Adapters::Output::Terminal::CLIProgressRenderer.new(
                terminal_service: c.resolve(:terminal_service)
              )
            end
            container.register_singleton(:wrapping_service) do |c|
              Shoko::Adapters::Output::Formatting::WrappingService.new(
                text_metrics: c.resolve(:text_metrics),
                async_executor: c.resolve(:async_executor),
                session_context: c.resolve_optional(:reader_session_context),
                config_reader: c.resolve(:config_reader),
                runtime_config: c.resolve_optional(:runtime_config),
                formatting_service_provider: -> { c.resolve_optional(:formatting_service) },
                document_provider: -> { c.resolve_optional(:document) },
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_singleton(:formatting_service) do |c|
              xhtml_factory = c.resolve_optional(:xhtml_parser_factory)
              logger = c.resolve_optional(:logger)
              Shoko::Adapters::Output::Formatting::FormattingService.new(
                xhtml_parser_factory: xhtml_factory,
                format_parser_resolver: build_format_parser_resolver(xhtml_factory, logger),
                runtime_config: c.resolve_optional(:runtime_config),
                logger: logger
              )
            end
            container.register_singleton(:epub_resource_loader) do |c|
              Shoko::Adapters::BookSources::Epub::EpubResourceLoader.new(
                cache_root: c.resolve(:cache_paths).cache_root,
                file_writer: c.resolve_optional(:atomic_file_writer),
                runtime_config: c.resolve_optional(:runtime_config),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_singleton(:kitty_image_renderer) do |c|
              loader = Shoko::Adapters::Output::Kitty::ResourceLoader.new(
                loader: c.resolve(:epub_resource_loader)
              )
              Shoko::Adapters::Output::Kitty::KittyImageRenderer.new(
                resource_loader: loader
              )
            end
            container.register_singleton(:wrapped_lines_provider) do |c|
              Shoko::Adapters::Runtime::SessionState::WrappedLinesProviderAdapter.new(
                formatting_service: c.resolve_optional(:formatting_service),
                session_context: c.resolve_optional(:reader_session_context)
              )
            end
            container.register_singleton(:file_writer) do |c|
              Shoko::Adapters::Storage::FileWriterService.new(
                atomic_file_writer: c.resolve_optional(:atomic_file_writer),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_singleton(:instrumentation_service) do |c|
              Shoko::Adapters::Output::InstrumentationService.new(
                performance_monitor: c.resolve_optional(:performance_monitor),
                perf_tracer: c.resolve_optional(:perf_tracer),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_singleton(:notification_service) do |c|
              Shoko::Adapters::Output::NotificationService.new(
                logger: c.resolve_optional(:logger),
                notification_writer: c.resolve_optional(:notification_writer)
              )
            end
            container.register_singleton(:ui_component_factory) do |_c|
              color_mode = begin
                Shoko::Adapters::Output::Terminal::Terminal.color_mode
              rescue StandardError
                :dark
              end
              Shoko::Adapters::Ui::Constants::Ui.apply_color_mode(color_mode)
              Shoko::Adapters::Ui::ComponentFactory.new(color_mode: color_mode)
            end
            container.register_singleton(:render_registry) { |_c| Shoko::Adapters::Ui::RenderRegistry.new }
            container.register_factory(:dictionary_catalog_service) do |c|
              Shoko::Adapters::Storage::DictionaryCatalogService.new(
                logger: c.resolve_optional(:logger)
              )
            end
          end

          # Register use case services
          def register_use_case_services(container)
            container.register_factory(:catalog_service) do |c|
              Shoko::Application::UseCases::CatalogService.new(
                library_scanner: c.resolve(:library_scanner),
                metadata_reader: c.resolve(:metadata_reader),
                cached_library_repository: c.resolve_optional(:cached_library_repository),
                recent_files_repository: c.resolve_optional(:recent_files_repository),
                logger: c.resolve_optional(:logger),
                file_probe: c.resolve_optional(:file_probe)
              )
            end
            container.register_factory(:download_service) do |c|
              config_storage = c.resolve_optional(:config_storage)
              downloads = config_storage ? File.join(config_storage.config_dir, 'downloads') : nil
              Shoko::Adapters::BookSources::DownloadService.new(
                gutendex_client: c.resolve(:gutendex_client),
                downloads_root: downloads,
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_factory(:settings_service) do |c|
              Shoko::Application::UseCases::SettingsService.new(
                config_reader: c.resolve(:config_reader),
                state_writer: c.resolve(:state_writer),
                terminal_service: c.resolve(:terminal_service),
                cache_manager: c.resolve(:cache_manager),
                dictionary_availability: c.resolve(:dictionary_availability),
                dictionary_storage: c.resolve(:dictionary_storage),
                data_cleanup: c.resolve(:data_cleanup),
                wrapping_service: c.resolve_optional(:wrapping_service),
                recent_files_repository: c.resolve_optional(:recent_files_repository),
                dictionary_service: c.resolve_optional(:dictionary_service),
                catalog_service: c.resolve_optional(:catalog_service),
                config_storage: c.resolve_optional(:config_storage),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_factory(:pagination_cache_preloader) do |c|
              Shoko::Application::Services::Pagination::PaginationCachePreloader.new(
                page_calculator: c.resolve(:page_calculator),
                pagination_cache: c.resolve(:pagination_cache),
                config_reader: c.resolve(:config_reader),
                reader_state_reader: c.resolve(:reader_state_reader),
                state_writer: c.resolve(:pagination_state_writer),
                display_capabilities: c.resolve(:display_capabilities),
                ui_state_reader: c.resolve(:ui_state_reader),
                sidebar_visible_reader: -> { c.resolve(:reader_overlay_state_reader).sidebar_visible? },
                logger: c.resolve_optional(:logger)
              )
            end
          end

          # Build a lambda that resolves the correct content parser for a chapter
          # based on its metadata[:format] hint. Falls back to the XHTML parser.
          def build_format_parser_resolver(xhtml_factory, logger)
            lambda { |raw, chapter|
              metadata = chapter&.respond_to?(:metadata) ? chapter.metadata : nil
              format = if metadata.is_a?(Hash)
                         metadata[:format] || metadata['format']
                       end

              format_key = format.to_s.strip.downcase
              if !format_key.empty? && format_key != 'epub'
                factory = Shoko::Core::BookFormats::FormatRegistry.content_parser_factory_for("dummy.#{format_key}")
                parser = factory&.call(raw, logger: logger)
                return parser if parser
              end

              xhtml_factory.call(raw) if xhtml_factory.respond_to?(:call)
            }
          end

          # Register document service factory
          def register_document_factory(container)
            container.register_factory(:document_service_factory) do |c|
              lambda { |path, progress_reporter: nil, background_worker: nil|
                build_document_service(c, path, progress_reporter, background_worker: background_worker)
              }
            end
          end

          # Build document service with resolved dependencies
          def build_document_service(container, path, progress_reporter, background_worker: nil)
            wrapper = container.resolve(:wrapping_service)
            formatting = container.resolve(:formatting_service)
            worker = background_worker || current_background_worker(container)
            logger = container.resolve(:logger)
            instrumentation = container.resolve_optional(:instrumentation_service)
            Shoko::Adapters::BookSources::DocumentService.new(
              path, wrapper,
              formatting_service: formatting,
              background_worker: worker,
              progress_reporter: progress_reporter,
              logger: logger,
              instrumentation: instrumentation,
              runtime_config: container.resolve_optional(:runtime_config)
            )
          end

          def current_background_worker(container)
            session_context = container.resolve_optional(:reader_session_context)
            session_worker = session_context&.background_worker
            return session_worker if session_worker

            container.registered?(:background_worker) ? container.resolve(:background_worker) : nil
          rescue StandardError
            nil
          end

          def current_reader_document(container)
            session_context = container.resolve_optional(:reader_session_context)
            session_document = session_context&.document
            return session_document if session_document

            container.resolve_optional(:document)
          rescue StandardError
            nil
          end
        end
      end
  end
end
