# frozen_string_literal: true

require_relative '../../adapters/ui/theme_context'

module Shoko
  module Composition
    module ContainerFactory
      # Registers rendering and instrumentation services used by test containers.
      module TestContainerRegistrationRenderingSupport
        private

        def register_test_rendering_services(container)
          register_test_cache_factories(container)
          register_test_instrumentation_services(container)
          register_test_render_adapters(container)
        end

        def register_test_cache_factories(container)
          test_logger = container.resolve(:logger)
          atomic_file_writer = container.resolve(:atomic_file_writer)
          register_test_epub_cache_factories(container, test_logger)
          container.register(:file_writer,
                             Shoko::Adapters::Storage::FileWriterService.new(
                               atomic_file_writer: atomic_file_writer
                             ))
        end

        def register_test_epub_cache_factories(container, test_logger)
          register_test_epub_cache_factory(container, test_logger)
          register_test_epub_cache_predicate(container)
          register_test_xhtml_parser_factory(container, test_logger)
        end

        def register_test_instrumentation_services(container)
          test_logger = container.resolve(:logger)
          performance_monitor = container.resolve(:performance_monitor)
          perf_tracer = container.resolve(:perf_tracer)
          register_test_performance_services(container, test_logger)
          instrumentation_service = Shoko::Adapters::Output::InstrumentationService.new(
            performance_monitor: performance_monitor,
            perf_tracer: perf_tracer,
            logger: test_logger
          )
          container.register(:instrumentation_service, instrumentation_service)
          container.register(:instrumentation, container.resolve(:instrumentation_service))
        end

        def register_test_performance_services(container, test_logger)
          runtime_config = container.resolve(:runtime_config)
          container.register(:performance_monitor,
                             Shoko::Adapters::Monitoring::PerformanceMonitor.new(logger: test_logger))
          container.register(:perf_tracer,
                             Shoko::Adapters::Monitoring::PerfTracer.new(
                               runtime_config: runtime_config
                             ))
        end

        def register_test_render_adapters(container)
          container.register(
            :text_metrics,
            Shoko::Adapters::Output::Terminal::TextMetricsPortAdapter.new(
              runtime_config: container.resolve(:runtime_config)
            )
          )
          container.register(:display_capabilities, Shoko::Adapters::Output::NullDisplayCapabilities.new)
          container.register(:async_executor, Shoko::Core::Services::InlineExecutor.new)
          container.register(:wrapped_lines_provider, Shoko::Adapters::Runtime::SessionState::WrappedLinesProviderAdapter.new)
        end
      end

      # Registers archive, metadata, and UI-session helpers for test containers.
      module TestContainerRegistrationArchiveSupport
        private

        def register_test_archive_services(container)
          register_test_archive_readers(container)
          register_test_metadata_services(container)
          register_test_ui_session_services(container)
        end

        def register_test_archive_readers(container)
          container.register(:archive_reader, Shoko::Adapters::BookSources::Archive::ZipReader)
          register_test_binary_readers(container)
          register_test_zip_readers(container)
        end

        def register_test_binary_readers(container)
          container.register(:binary_file_reader, ->(path) { File.binread(path) })
          container.register(:utf8_file_reader, ->(path) { File.read(path, encoding: 'UTF-8') })
        end

        def register_test_zip_readers(container)
          runtime_config = container.resolve(:runtime_config)
          container.register(:zip_open,
                             lambda do |path, &block|
                               container.resolve(:archive_reader).open(path, runtime_config: runtime_config, &block)
                             end)
          container.register(:zip_entry_reader, build_test_zip_entry_reader(container))
        end

        def build_test_zip_entry_reader(container)
          runtime_config = container.resolve(:runtime_config)
          lambda do |path, suffix|
            container.resolve(:archive_reader).open(path, runtime_config: runtime_config) do |zip|
              entry = zip.entries.find { |item| item.name.downcase.end_with?(suffix.to_s.downcase) }
              entry ? zip.read(entry.name) : nil
            end
          end
        end

        def register_test_metadata_services(container)
          container.register(:metadata_reader, build_test_metadata_reader(container))
          container.register(:input_system_factory, Shoko::Adapters::Input::InputSystemFactoryAdapter.new)
          container.register(:rendering_factory, Shoko::Adapters::Ui::RenderingFactory.new)
          container.register(:render_registry, Shoko::Adapters::Ui::RenderRegistry.new)
        end

        def register_test_ui_session_services(container)
          annotation_overlay_ui_session = register_test_annotation_overlay_ui_session(container)
          register_test_translation_service(container)
          register_test_annotation_editor_launcher(container, annotation_overlay_ui_session)
          register_test_render_state_writer(container)
        end

        def register_test_annotation_overlay_ui_session(container)
          session = RSpec::Mocks::Double.new('AnnotationOverlayUiSession', open_editor: nil)
          container.register(:annotation_overlay_ui_session, session)
          session
        end

        def register_test_translation_service(container)
          container.register(
            :translation_service,
            RSpec::Mocks::Double.new('TranslationService', translate: nil, available_languages: [])
          )
        end

        def register_test_annotation_editor_launcher(container, annotation_overlay_ui_session)
          container.register(
            :annotation_editor_launcher,
            Shoko::Adapters::Ui::Sessions::AnnotationEditorLauncherAdapter.new(
              annotation_overlay_ui_session: annotation_overlay_ui_session
            )
          )
        end

        def register_test_render_state_writer(container)
          container.register(
            :render_state_writer,
            RSpec::Mocks::Double.new(
              'RenderedLineStateSink',
              clear_rendered_lines: nil,
              update_rendered_lines: nil
            )
          )
        end
      end

      # Registers test container wiring and defaults.
      module TestContainerRegistration
        include TestContainerRegistrationArchiveSupport
        include TestContainerRegistrationRenderingSupport

        # Create container with mocked services for testing
        #
        # @return [DependencyContainer]
        def create_test_container
          require 'rspec/mocks'

          container = DependencyContainer.new
          register_test_mocks(container)
          register_test_infrastructure(container)
          apply_test_configuration(container)
          container
        end

        def apply_test_configuration(container)
          Shoko::TestSupport::TestMode.configure_container(container) if defined?(Shoko::TestSupport::TestMode)
        end

        private

        def register_test_mocks(container)
          container.register(:event_bus, RSpec::Mocks::Double.new('EventBus', subscribe: nil, emit_event: nil))
          container.register(:state_store,
                             RSpec::Mocks::Double.new('StateStore', get: nil, set: nil, current_state: {}))
          container.register(:logger, Shoko::Core::Services::NullLogger.new)
        end

        def register_test_infrastructure(container)
          register_test_runtime_services(container)
          register_test_rendering_services(container)
          register_test_ui_services(container)
          register_test_event_services(container)
          register_test_archive_services(container)
        end

        def register_test_runtime_services(container)
          register_test_storage_services(container)
          register_test_runtime_adapters(container)
          register_test_terminal_services(container)
        end

        def register_test_storage_services(container)
          container.register(:atomic_file_writer, Shoko::Adapters::Storage::AtomicFileWriter)
          container.register(:cache_paths, Shoko::Adapters::Storage::CachePaths)
          container.register(:cache_pointer_resolver, Shoko::Adapters::Storage::CachePointerResolver.new)
          container.register(:cache_availability,
                             Shoko::Adapters::Storage::CacheAvailabilityAdapter.new(
                               cache_root: Shoko::Adapters::Storage::CachePaths.cache_root,
                               logger: container.resolve(:logger)
                             ))
          container.register(:book_file_probe, Shoko::Adapters::BookSources::BookFileProbe.new)
          container.register(:file_probe, Shoko::Adapters::Storage::FileProbeAdapter.new)
          container.register(:path_ops, Shoko::Adapters::Storage::PathOpsAdapter.new)
          container.register(:recent_files_repository, Shoko::Adapters::Storage::RecentFilesRepository.new)
        end

        def register_test_runtime_adapters(container)
          container.register(:process_control, Shoko::Adapters::Runtime::ProcessControlAdapter.new)
          container.register(:clock, Shoko::Adapters::Runtime::MonotonicClockAdapter.new)
          container.register(:wall_clock, RSpec::Mocks::Double.new('WallClock', utc_now: Time.utc(2024, 1, 1, 0, 0, 0)))
          container.register(:id_generator, RSpec::Mocks::Double.new('IdGenerator', uuid: 'test-event-id'))
          container.register(:runtime_config, Shoko::Adapters::Runtime::EnvRuntimeConfigAdapter.new)
          Shoko::Shared::Terminal::TextMetrics.configure_runtime_config!(
            runtime_config: container.resolve(:runtime_config)
          )
        end

        def register_test_terminal_services(container)
          terminal_service = RSpec::Mocks::Double.new('TerminalService', setup: nil, cleanup: nil, size: [24, 80])
          container.register(:terminal_service, terminal_service)
          container.register(
            :terminal_session,
            Shoko::Adapters::Output::Terminal::TerminalSessionAdapter.new(terminal_service: terminal_service)
          )
          container.register(:app_mode_runner,
                             RSpec::Mocks::Double.new('AppModeRunner', run_reader: nil, run_menu: nil))
        end

        def register_test_ui_services(container)
          register_test_ui_component_factory(container)
          register_test_book_services(container)
          register_test_terminal_ui_services(container)
        end

        def register_test_ui_component_factory(container)
          test_config_reader = build_test_config_reader
          test_theme_context = Shoko::Adapters::Ui::ThemeContext.apply!(theme_id: test_config_reader.theme)
          container.register(
            :ui_component_factory,
            Shoko::Adapters::Ui::ComponentFactory.new(
              config_reader: test_config_reader,
              fallback_color_mode: test_theme_context.color_mode
            )
          )
        end

        def build_test_config_reader
          RSpec::Mocks::Double.new(
            'ConfigReader',
            page_numbering_mode: :dynamic,
            view_mode: :single,
            line_spacing: :normal,
            dictionary_source_lang: nil,
            dictionary_target_lang: nil,
            dictionary_path: nil,
            dictionary_backend: nil,
            theme: :default
          )
        end

        def register_test_book_services(container)
          container.register(:config_storage, Shoko::Adapters::Storage::ConfigStorageAdapter.new)
          test_book_finder = Shoko::Adapters::BookSources::BookFinder.new(
            config_root: container.resolve(:config_storage).config_dir,
            cache_writer: container.resolve(:atomic_file_writer),
            book_file_probe: container.resolve(:book_file_probe),
            logger: container.resolve(:logger)
          )
          container.register(:book_finder, test_book_finder)
        end

        def register_test_terminal_ui_services(container)
          container.register(:terminal_capabilities, Shoko::Adapters::Output::Terminal::NullTerminalCapabilities.new)
          container.register(:layout_metrics, Shoko::Core::Services::DefaultLayoutMetrics.new)
        end

        def register_test_event_services(container)
          register_test_domain_event_services(container)
          register_test_dictionary_services(container)
        end

        def register_test_domain_event_services(container)
          register_test_event_publisher(container)
          register_test_domain_event_bus(container)
          register_test_domain_event_factory(container)
          register_test_input_helpers(container)
        end

        def register_test_dictionary_services(container)
          epub_cache_clearer = lambda do
            container.resolve(:book_finder).clear_cache
          end
          container.register(:dictionary_availability,
                             Shoko::Adapters::Storage::DictionaryAvailabilityAdapter.new(
                               backend_class: Shoko::Adapters::Storage::SqliteDictionaryAdapter
                             ))
          container.register(:dictionary_storage, Shoko::Adapters::Storage::DictionaryStorageAdapter.new)
          container.register(:data_cleanup, Shoko::Adapters::Storage::DataCleanupAdapter.new)
          container.register(:cache_manager,
                             Shoko::Adapters::Storage::CacheManagerAdapter.new(
                               epub_cache_clearer: epub_cache_clearer,
                               cache_path_provider: Shoko::Adapters::Storage::CachePaths
                             ))
        end

        def register_test_epub_cache_factory(container, test_logger)
          container.register(:epub_cache_factory,
                             lambda { |path|
                               Shoko::Adapters::Storage::EpubCache.new(
                                 path,
                                 logger: test_logger,
                                 runtime_config: container.resolve(:runtime_config)
                               )
                             })
        end

        def register_test_epub_cache_predicate(container)
          container.register(:epub_cache_predicate, ->(path) { Shoko::Adapters::Storage::EpubCache.cache_file?(path) })
        end

        def register_test_xhtml_parser_factory(container, test_logger)
          container.register(:xhtml_parser_factory,
                             lambda do |raw|
                               require_relative '../../adapters/book_sources/epub/parser/xhtml_content_parser'
                               Shoko::Adapters::BookSources::Epub::XHTMLContentParser.new(raw, logger: test_logger)
                             end)
        end

        def build_test_metadata_reader(container)
          Shoko::Adapters::BookSources::MetadataReaderAdapter.new(
            file_probe: container.resolve(:file_probe),
            path_ops: container.resolve(:path_ops),
            file_reader: container.resolve(:binary_file_reader),
            text_reader: container.resolve(:utf8_file_reader),
            zip_open: container.resolve(:zip_open),
            zip_entry_reader: container.resolve(:zip_entry_reader)
          )
        end

        def register_test_event_publisher(container)
          container.register(:event_publisher,
                             Shoko::Adapters::Runtime::SessionState::EventPublisherAdapter.new(
                               event_bus: container.resolve(:event_bus)
                             ))
        end

        def register_test_domain_event_bus(container)
          container.register(:domain_event_bus,
                             Shoko::Core::Events::DomainEventBus.new(
                               event_publisher: container.resolve(:event_publisher),
                               logger: container.resolve(:logger)
                             ))
        end

        def register_test_domain_event_factory(container)
          container.register(:domain_event_factory,
                             Shoko::Core::Events::EventFactory.new(
                               wall_clock: container.resolve(:wall_clock),
                               id_generator: container.resolve(:id_generator)
                             ))
        end

        def register_test_input_helpers(container)
          container.register(:key_classifier,
                             Shoko::Adapters::Input::KeyClassifierAdapter.new(
                               command_factory: Shoko::Adapters::Input::CommandFactory
                             ))
          container.register(:text_sanitizer, Shoko::Adapters::Output::Terminal::TextSanitizerAdapter.new)
        end
      end
    end
  end
end
