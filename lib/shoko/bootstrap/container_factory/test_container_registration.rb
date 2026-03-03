# frozen_string_literal: true

module Shoko
  module Bootstrap
    module ContainerFactory
      # Registers test container wiring and defaults.
      module TestContainerRegistration
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
          container.register(:atomic_file_writer, Shoko::Adapters::Storage::AtomicFileWriter)
          container.register(:cache_paths, Shoko::Adapters::Storage::CachePaths)
          container.register(:cache_pointer_resolver, Shoko::Adapters::Storage::CachePointerResolver.new)
          container.register(:cache_availability,
                             Shoko::Adapters::Storage::CacheAvailabilityAdapter.new(
                               cache_root: Shoko::Adapters::Storage::CachePaths.cache_root,
                               logger: container.resolve(:logger)
                             ))
          container.register(:file_probe, Shoko::Adapters::Storage::FileProbeAdapter.new)
          container.register(:path_ops, Shoko::Adapters::Storage::PathOpsAdapter.new)
          container.register(:process_control, Shoko::Adapters::Runtime::ProcessControlAdapter.new)
          container.register(:clock, Shoko::Adapters::Runtime::MonotonicClockAdapter.new)
          container.register(:wall_clock, RSpec::Mocks::Double.new('WallClock', utc_now: Time.utc(2024, 1, 1, 0, 0, 0)))
          container.register(:id_generator, RSpec::Mocks::Double.new('IdGenerator', uuid: 'test-event-id'))
          container.register(:runtime_config, Shoko::Adapters::Runtime::EnvRuntimeConfigAdapter.new)
          Shoko::Shared::Terminal::TextMetrics.configure_runtime_config!(
            runtime_config: container.resolve(:runtime_config)
          )
          terminal_service = RSpec::Mocks::Double.new('TerminalService', setup: nil, cleanup: nil, size: [24, 80])
          container.register(:terminal_service, terminal_service)
          container.register(:terminal_session, Shoko::Adapters::Output::Terminal::TerminalSessionAdapter.new(
                                               terminal_service: terminal_service
                                             ))
          container.register(:app_mode_runner, RSpec::Mocks::Double.new('AppModeRunner', run_reader: nil, run_menu: nil))
          container.register(:recent_files_repository, Shoko::Adapters::Storage::RecentFilesRepository.new)
          test_logger = container.resolve(:logger)
          container.register(:epub_cache_factory, lambda { |path|
            Shoko::Adapters::Storage::EpubCache.new(
              path,
              logger: test_logger,
              runtime_config: container.resolve(:runtime_config)
            )
          })
          container.register(:epub_cache_predicate, ->(path) { Shoko::Adapters::Storage::EpubCache.cache_file?(path) })
          container.register(:xhtml_parser_factory, lambda { |raw|
            Shoko::Core::BookFormats::Epub::XHTMLContentParser.new(raw, logger: test_logger)
          })
          container.register(:file_writer, Shoko::Adapters::Storage::FileWriterService.new(
                                             atomic_file_writer: container.resolve(:atomic_file_writer)
                                           ))
          container.register(:performance_monitor,
                             Shoko::Adapters::Monitoring::PerformanceMonitor.new(logger: test_logger))
          container.register(:perf_tracer, Shoko::Adapters::Monitoring::PerfTracer.new(
                                           runtime_config: container.resolve(:runtime_config)
                                         ))
          container.register(:instrumentation_service, Shoko::Adapters::Output::InstrumentationService.new(
                                                         performance_monitor: container.resolve(:performance_monitor),
                                                         perf_tracer: container.resolve(:perf_tracer),
                                                         logger: test_logger
                                                       ))
          container.register(:instrumentation, container.resolve(:instrumentation_service))
          container.register(
            :text_metrics,
            Shoko::Adapters::Output::Terminal::TextMetricsPortAdapter.new(
              runtime_config: container.resolve(:runtime_config)
            )
          )
          container.register(:display_capabilities, Shoko::Core::Services::DefaultDisplayCapabilities.new)
          container.register(:async_executor, Shoko::Core::Services::InlineExecutor.new)
          container.register(:wrapped_lines_provider, Shoko::Adapters::Runtime::SessionState::WrappedLinesProviderAdapter.new)
          Shoko::Adapters::Ui::Constants::Ui.apply_color_mode(:dark)
          container.register(:ui_component_factory,
                             Shoko::Adapters::Ui::ComponentFactory.new(color_mode: :dark))
          container.register(:config_storage, Shoko::Adapters::Storage::ConfigStorageAdapter.new)
          test_book_finder = Shoko::Adapters::BookSources::BookFinder.new(
            config_root: container.resolve(:config_storage).config_dir,
            cache_writer: container.resolve(:atomic_file_writer),
            logger: container.resolve(:logger)
          )
          container.register(:book_finder, test_book_finder)
          container.register(:terminal_capabilities, Shoko::Core::Services::DefaultTerminalCapabilities.new)
          container.register(:layout_metrics, Shoko::Core::Services::DefaultLayoutMetrics.new)
          container.register(:event_publisher, Shoko::Adapters::Runtime::SessionState::EventPublisherAdapter.new(
                                               event_bus: container.resolve(:event_bus)
                                             ))
          container.register(:domain_event_bus, Shoko::Core::Events::DomainEventBus.new(
                                                  event_publisher: container.resolve(:event_publisher),
                                                  logger: container.resolve(:logger)
                                                ))
          container.register(:domain_event_factory, Shoko::Core::Events::EventFactory.new(
                                                      wall_clock: container.resolve(:wall_clock),
                                                      id_generator: container.resolve(:id_generator)
                                                    ))
          container.register(:key_classifier, Shoko::Adapters::Input::KeyClassifierAdapter.new(
                                                command_factory: Shoko::Adapters::Input::CommandFactory
                                              ))
          container.register(:command_bus, Shoko::Application::UseCases::CommandBus.new)
          container.register(:text_sanitizer, Shoko::Adapters::Output::Terminal::TextSanitizerAdapter.new)
          container.register(:dictionary_availability, Shoko::Adapters::Storage::DictionaryAvailabilityAdapter.new(
                                                         backend_class: Shoko::Adapters::Storage::SqliteDictionaryAdapter
                                                       ))
          container.register(:dictionary_storage, Shoko::Adapters::Storage::DictionaryStorageAdapter.new)
          container.register(:data_cleanup, Shoko::Adapters::Storage::DataCleanupAdapter.new)
          container.register(:cache_manager, Shoko::Adapters::Storage::CacheManagerAdapter.new(
                                               epub_cache_clearer: lambda {
                                                 container.resolve(:book_finder).clear_cache
                                               },
                                               cache_path_provider: Shoko::Adapters::Storage::CachePaths
                                             ))
          container.register(:metadata_reader, Shoko::Adapters::BookSources::MetadataReaderAdapter.new(
                                                 extractor: Shoko::Core::BookFormats::Epub::MetadataExtractor,
                                                 runtime_config: container.resolve(:runtime_config)
                                               ))
          container.register(:input_system_factory, Shoko::Adapters::Input::InputSystemFactoryAdapter.new)
          container.register(:rendering_factory, Shoko::Adapters::Ui::RenderingFactory.new)
          container.register(:render_registry, Shoko::Adapters::Ui::RenderRegistry.new)
          reader_state_reader = RSpec::Mocks::Double.new('ReaderStateReader',
                                                         current_chapter: 0, total_chapters: 1,
                                                         current_page_index: 0, left_page: 0,
                                                         right_page: 0, single_page: 0,
                                                         current_page: 0, page_map: [],
                                                         book_path: nil, bookmarks: [])
          container.register(:reader_state_reader, reader_state_reader)
          container.register(:reader_navigation_reader, reader_state_reader)
          container.register(:ui_state_reader, RSpec::Mocks::Double.new('UIStateReader',
                                                                        terminal_width: 80, terminal_height: 24))
          container.register(:config_reader, RSpec::Mocks::Double.new('ConfigReader',
                                                                      page_numbering_mode: :dynamic,
                                                                      view_mode: :single, line_spacing: :normal,
                                                                      dictionary_source_lang: nil,
                                                                      dictionary_target_lang: nil,
                                                                      dictionary_path: nil,
                                                                      dictionary_backend: nil))
          state_writer = RSpec::Mocks::Double.new('StateWriter',
                                                  update_pagination_state: nil,
                                                  update_page: nil, update_selections: nil,
                                                  update_ui_loading: nil, update_reader: nil,
                                                  update_navigation: nil, update_bookmarks: nil)
          container.register(:state_writer, state_writer)
          container.register(:pagination_state_writer, state_writer)
          container.register(:reader_state_writer, state_writer)
          annotation_overlay_ui_session = RSpec::Mocks::Double.new('AnnotationOverlayUiSession', open_editor: nil)
          container.register(:annotation_overlay_ui_session, annotation_overlay_ui_session)
          container.register(:annotation_editor_launcher, Shoko::Adapters::Ui::Sessions::AnnotationEditorLauncherAdapter.new(
                                                           annotation_overlay_ui_session: annotation_overlay_ui_session
                                                         ))
          menu_state_reader = RSpec::Mocks::Double.new('MenuStateReader',
                                                       selected: 0, mode: :main, browse_selected: 0,
                                                       search_query: '', search_cursor: 0,
                                                       search_active?: false, settings_selected: 0,
                                                       download_query: '', download_cursor: 0,
                                                       download_selected: 0, download_status: nil,
                                                       download_progress: nil, dictionary_query: '',
                                                       dictionary_cursor: 0, dictionary_selected: 0,
                                                       dictionary_status: nil, dictionary_progress: nil,
                                                       download_next: nil, download_prev: nil)
          container.register(:menu_state_reader, menu_state_reader)
          container.register(:render_state_writer, RSpec::Mocks::Double.new('RenderStateWriter',
                                                                            clear_rendered_lines: nil,
                                                                            update_rendered_lines: nil))
          container.register(:sidebar_state_reader, RSpec::Mocks::Double.new('SidebarStateReader',
                                                                             sidebar_visible?: false,
                                                                             sidebar_active_tab: :toc,
                                                                             sidebar_toc_selected: 0,
                                                                             sidebar_toc_collapsed: {},
                                                                             sidebar_bookmarks_selected: 0,
                                                                             sidebar_annotations_selected: 0,
                                                                             sidebar_prev_view_mode: nil,
                                                                             sidebar_toc_filter: nil,
                                                                             sidebar_toc_filter_active?: false))
        end
      end
    end
  end
end
