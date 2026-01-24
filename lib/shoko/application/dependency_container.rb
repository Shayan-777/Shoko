# frozen_string_literal: true

require 'set'
require_relative '../adapters/storage/background_worker'
require_relative '../adapters/storage/atomic_file_writer'
require_relative '../adapters/monitoring/performance_monitor'
require_relative '../adapters/monitoring/perf_tracer'
require_relative '../adapters/monitoring/logger_adapter'
require_relative '../core/services/null_logger'
require_relative '../adapters/storage/pagination_cache'
require_relative '../adapters/storage/cache_paths'
require_relative '../adapters/storage/epub_cache'
require_relative '../adapters/output/kitty/kitty_image_renderer'
require_relative '../adapters/output/kitty/display_capabilities'
require_relative '../adapters/output/terminal/text_metrics'
require_relative '../adapters/book_sources/gutendex_client'
require_relative '../adapters/storage/repositories/cached_library_repository'
require_relative '../adapters/book_sources/epub/parsers/xhtml_content_parser'
require_relative '../adapters/output/render_registry'
require_relative '../core/events/domain_event_bus'
require_relative '../core/services/default_display_capabilities'
require_relative '../core/services/inline_executor'
require_relative '../adapters/storage/file_writer_service'
require_relative '../adapters/storage/dictionary_catalog_service'
require_relative '../adapters/storage/sqlite_dictionary_adapter'
require_relative '../adapters/storage/config_storage_adapter'
require_relative '../adapters/output/instrumentation_service'
require_relative '../adapters/output/terminal_capabilities_adapter'
require_relative '../adapters/book_sources/download_service'
require_relative '../core/services/dictionary_service'
require_relative '../core/services/default_terminal_capabilities'
require_relative '../core/services/default_layout_metrics'
require_relative 'adapters/config_reader_adapter'
require_relative 'adapters/layout_metrics_adapter'
require_relative 'adapters/state_writer_adapter'
require_relative 'adapters/rendered_content_reader_adapter'
require_relative 'adapters/reader_state_reader_adapter'
require_relative 'adapters/ui_state_reader_adapter'
require_relative 'adapters/render_state_writer_adapter'
require_relative 'adapters/progress_state_reader_adapter'
require_relative 'adapters/sidebar_state_reader_adapter'

module Shoko
  module Application
    # Dependency injection container for managing service dependencies.
    # Replaces the broken ServiceRegistry with proper lifecycle management.
    class DependencyContainer
      class DependencyError < StandardError; end
      class CircularDependencyError < DependencyError; end

      def initialize
        @services = {}
        @factories = {}
        @singletons = {}
        @resolving = Set.new
      end

      # Register a singleton service
      #
      # @param name [Symbol] Service name
      # @param service [Object] Service instance
      def register(name, service)
        @services[name] = service
      end

      # Register a factory for lazy instantiation
      #
      # @param name [Symbol] Service name
      # @param factory [Proc] Factory proc that creates the service
      def register_factory(name, &factory)
        @factories[name] = factory
      end

      # Register a singleton factory
      #
      # @param name [Symbol] Service name
      # @param factory [Proc] Factory proc
      def register_singleton(name, &factory)
        @singletons[name] = factory
      end

      # Resolve a service by name
      #
      # @param name [Symbol] Service name
      # @return [Object] Service instance
      def resolve(name)
        return @services[name] if @services.key?(name)

        detect_circular_dependency(name) do
          resolve_from_factories(name)
        end
      end

      # Resolve multiple services
      #
      # @param names [Array<Symbol>] Service names
      # @return [Hash<Symbol, Object>] Hash of name => service
      def resolve_many(*names)
        names.to_h { |name| [name, resolve(name)] }
      end

      # Resolve a service by name, returning nil if not registered
      #
      # @param name [Symbol] Service name
      # @return [Object, nil] Service instance or nil
      def resolve_optional(name)
        return nil unless registered?(name)

        resolve(name)
      rescue DependencyError, StandardError
        nil
      end

      # Check if service is registered
      #
      # @param name [Symbol] Service name
      # @return [Boolean]
      def registered?(name)
        @services.key?(name) || @factories.key?(name) || @singletons.key?(name)
      end

      # List all registered service names
      #
      # @return [Array<Symbol>]
      def service_names
        (@services.keys + @factories.keys + @singletons.keys).uniq
      end

      # Create child container with inherited services
      #
      # @return [DependencyContainer]
      def create_child
        child = self.class.new
        child.instance_variable_set(:@services, @services.dup)
        child.instance_variable_set(:@factories, @factories.dup)
        child.instance_variable_set(:@singletons, @singletons.dup)
        child
      end

      # Clear all registrations (for testing)
      def clear!
        @services.clear
        @factories.clear
        @singletons.clear
      end

      private

      def resolve_from_factories(name)
        if @singletons.key?(name)
          @services[name] ||= @singletons[name].call(self)
        elsif @factories.key?(name)
          @factories[name].call(self)
        else
          raise DependencyError, "Service '#{name}' not registered"
        end
      end

      def detect_circular_dependency(name)
        if @resolving.include?(name)
          raise CircularDependencyError,
                "Circular dependency detected for '#{name}'"
        end

        @resolving.add(name)
        begin
          yield
        ensure
          @resolving.delete(name)
        end
      end
    end

    # Factory methods for common service configurations
    module ContainerFactory
      class << self
        # Create a fully configured dependency container
        #
        # @return [DependencyContainer]
        def create_default_container
          container = DependencyContainer.new
          event_bus = register_infrastructure(container)
          register_core_ports(container)
          register_repositories(container)
          register_domain_services(container)
          register_application_services(container)
          register_state_management(container, event_bus)
          register_library_services(container)
          apply_test_configuration(container)
          container
        end

        private

        # Register core infrastructure services (logging, caching, events)
        def register_infrastructure(container)
          # Register logger first so other services can use it
          container.register_singleton(:logger) { |_c| Shoko::Adapters::Monitoring::LoggerAdapter.new }
          container.register_singleton(:event_bus) do |c|
            Shoko::Application::Infrastructure::EventBus.new(logger: c.resolve(:logger))
          end
          container.register(:performance_monitor, Shoko::Adapters::Monitoring::PerformanceMonitor)
          container.register(:perf_tracer, Shoko::Adapters::Monitoring::PerfTracer)
          container.register(:pagination_cache, Shoko::Adapters::Storage::PaginationCache)
          container.register(:cache_paths, Shoko::Adapters::Storage::CachePaths)
          container.register(:atomic_file_writer, Shoko::Adapters::Storage::AtomicFileWriter)
          register_epub_cache_factories(container)
          register_worker_factories(container)

          # Domain event bus (capture event_bus early)
          event_bus = container.resolve(:event_bus)
          container.register_singleton(:domain_event_bus) { |_c| Shoko::Core::Events::DomainEventBus.new(event_bus) }
          event_bus
        end

        # Register core port adapters.
        def register_core_ports(container)
          container.register(:text_metrics, Shoko::Adapters::Output::Terminal::TextMetrics)
          container.register_singleton(:display_capabilities) do |_c|
            Shoko::Adapters::Output::Kitty::DisplayCapabilities.new
          end
          container.register_singleton(:instrumentation) { |c| c.resolve(:instrumentation_service) }
          container.register_factory(:async_executor) do |c|
            executor = if c.registered?(:background_worker)
                         c.resolve(:background_worker)
                       end
            executor || Shoko::Core::Services::InlineExecutor.new
          rescue StandardError
            Shoko::Core::Services::InlineExecutor.new
          end

          # New hexagonal ports
          container.register_singleton(:config_storage) do |_c|
            Shoko::Adapters::Storage::ConfigStorageAdapter.new
          end
          container.register_singleton(:terminal_capabilities) do |_c|
            Shoko::Adapters::Output::TerminalCapabilitiesAdapter.new
          end
          container.register_singleton(:layout_metrics) do |_c|
            Shoko::Application::Adapters::LayoutMetricsAdapter.new
          end
        end

        # Register EPUB cache factory lambdas
        def register_epub_cache_factories(container)
          container.register(:epub_cache_factory, ->(path) { Shoko::Adapters::Storage::EpubCache.new(path) })
          container.register(:epub_cache_predicate, ->(path) { Shoko::Adapters::Storage::EpubCache.cache_file?(path) })
          container.register_singleton(:gutendex_client) do |c|
            Shoko::Adapters::BookSources::GutendexClient.new(logger: c.resolve(:logger))
          end
        end

        # Register background worker and parser factories
        def register_worker_factories(container)
          container.register(:background_worker_factory, lambda { |name: 'shoko-worker', logger:|
            Shoko::Adapters::Storage::BackgroundWorker.new(name: name, logger: logger)
          })
          container.register(:xhtml_parser_factory, lambda { |raw|
            Shoko::Adapters::BookSources::Epub::Parsers::XHTMLContentParser.new(raw)
          })
        end

        # Register repository implementations
        def register_repositories(container)
          container.register_factory(:bookmark_repository) do |c|
            Shoko::Adapters::Storage::Repositories::BookmarkRepository.new(
              file_writer: c.resolve(:file_writer),
              logger: c.resolve_optional(:logger)
            )
          end
          container.register_factory(:annotation_repository) do |c|
            Shoko::Adapters::Storage::Repositories::AnnotationRepository.new(
              file_writer: c.resolve(:file_writer),
              logger: c.resolve_optional(:logger)
            )
          end
          container.register_factory(:progress_repository) do |c|
            Shoko::Adapters::Storage::Repositories::ProgressRepository.new(
              file_writer: c.resolve(:file_writer),
              logger: c.resolve_optional(:logger)
            )
          end
          container.register_factory(:config_repository) do |c|
            Shoko::Adapters::Storage::Repositories::ConfigRepository.new(
              global_state: c.resolve(:global_state),
              logger: c.resolve_optional(:logger)
            )
          end
        end

        # Register core domain services
        def register_domain_services(container)
          container.register_factory(:navigation_service) { |c| Shoko::Core::Services::NavigationService.new(c) }
          container.register_factory(:bookmark_service) { |c| Shoko::Core::Services::BookmarkService.new(c) }
          container.register_singleton(:page_calculator) { |c| Shoko::Core::Services::PageCalculatorService.new(c) }
          container.register_factory(:coordinate_service) { |c| Shoko::Core::Services::CoordinateService.new(c) }
          container.register_factory(:selection_service) { |c| Shoko::Core::Services::SelectionService.new(c) }
          container.register_factory(:layout_service) { |c| Shoko::Core::Services::LayoutService.new(c) }
          container.register_factory(:annotation_service) { |c| Shoko::Core::Services::AnnotationService.new(c) }
          container.register_factory(:dictionary_service) { |c| Shoko::Core::Services::DictionaryService.new(c) }
          container.register_factory(:dictionary_repository) do |c|
            config_reader = begin
              c.resolve(:config_reader)
            rescue StandardError
              nil
            end
            backend = config_reader&.dictionary_backend
            backend_name = backend.to_s.downcase
            env_enabled = ENV['SHOKO_DICTIONARY'].to_s.downcase == 'sqlite'
            enabled = if env_enabled
                        true
                      elsif backend_name == 'disabled'
                        false
                      elsif backend_name == 'sqlite'
                        true
                      else
                        dict_path = config_reader&.dictionary_path
                        Shoko::Adapters::Storage::SqliteDictionaryAdapter.databases_present?(dict_path)
                      end

            next unless enabled

            dict_path = config_reader&.dictionary_path
            Shoko::Adapters::Storage::SqliteDictionaryAdapter.new(databases_path: dict_path)
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
              logger: c.resolve_optional(:logger)
            )
          end
          container.register_singleton(:wrapping_service) do |c|
            Shoko::Adapters::Output::Formatting::WrappingService.new(
              text_metrics: c.resolve(:text_metrics),
              async_executor: c.resolve(:async_executor),
              dependencies: c,
              config_reader: c.resolve(:config_reader),
              logger: c.resolve_optional(:logger)
            )
          end
          container.register_singleton(:formatting_service) do |c|
            Shoko::Adapters::Output::Formatting::FormattingService.new(
              xhtml_parser_factory: c.resolve_optional(:xhtml_parser_factory),
              logger: c.resolve_optional(:logger)
            )
          end
          container.register_singleton(:kitty_image_renderer) { |_c| Shoko::Adapters::Output::Kitty::KittyImageRenderer.new }
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
              logger: c.resolve_optional(:logger)
            )
          end
          container.register_singleton(:render_registry) { |_c| Shoko::Adapters::Output::RenderRegistry.current }
          container.register_factory(:dictionary_catalog_service) do |c|
            Shoko::Adapters::Storage::DictionaryCatalogService.new(
              logger: c.resolve_optional(:logger)
            )
          end
        end

        # Register use case services
        def register_use_case_services(container)
          container.register_factory(:catalog_service) { |c| Shoko::Application::UseCases::CatalogService.new(c) }
          container.register_factory(:download_service) do |c|
            Shoko::Adapters::BookSources::DownloadService.new(
              gutendex_client: c.resolve(:gutendex_client),
              logger: c.resolve_optional(:logger)
            )
          end
          container.register_factory(:settings_service) { |c| Shoko::Application::UseCases::SettingsService.new(c) }
          container.register_factory(:pagination_cache_preloader) do |c|
            Shoko::Core::Services::Pagination::PaginationCachePreloader.new(
              page_calculator: c.resolve(:page_calculator),
              pagination_cache: c.resolve(:pagination_cache),
              config_reader: c.resolve(:config_reader),
              reader_state_reader: c.resolve(:reader_state_reader),
              state_writer: c.resolve(:state_writer),
              display_capabilities: c.resolve(:display_capabilities),
              ui_state_reader: c.resolve(:ui_state_reader),
              logger: c.resolve_optional(:logger)
            )
          end
        end

        # Register document service factory
        def register_document_factory(container)
          container.register_factory(:document_service_factory) do |c|
            lambda { |path, progress_reporter: nil|
              build_document_service(c, path, progress_reporter)
            }
          end
        end

        # Build document service with resolved dependencies
        def build_document_service(container, path, progress_reporter)
          wrapper = container.resolve(:wrapping_service)
          formatting = container.resolve(:formatting_service)
          worker = container.registered?(:background_worker) ? container.resolve(:background_worker) : nil
          logger = container.resolve(:logger)
          Shoko::Adapters::BookSources::DocumentService.new(
            path, wrapper,
            formatting_service: formatting,
            background_worker: worker,
            progress_reporter: progress_reporter,
            logger: logger
          )
        end

        # Register state management services
        def register_state_management(container, event_bus)
          container.register_singleton(:global_state) do |c|
            Shoko::Application::Infrastructure::ObserverStateStore.new(
              event_bus,
              config_storage: c.resolve(:config_storage),
              terminal_capabilities: c.resolve(:terminal_capabilities)
            )
          end
          container.register_factory(:state_store) { |c| c.resolve(:global_state) }
          register_hexagonal_adapters(container)
        end

        # Register hexagonal architecture port adapters
        def register_hexagonal_adapters(container)
          container.register_factory(:config_reader) do |c|
            Shoko::Application::Adapters::ConfigReaderAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:state_writer) do |c|
            Shoko::Application::Adapters::StateWriterAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:rendered_content_reader) do |c|
            Shoko::Application::Adapters::RenderedContentReaderAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:reader_state_reader) do |c|
            Shoko::Application::Adapters::ReaderStateReaderAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:ui_state_reader) do |c|
            Shoko::Application::Adapters::UIStateReaderAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:render_state_writer) do |c|
            Shoko::Application::Adapters::RenderStateWriterAdapter.new(c.resolve(:global_state), logger: c.resolve(:logger))
          end
          container.register_factory(:progress_state_reader) do |c|
            Shoko::Application::Adapters::ProgressStateReaderAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:sidebar_state_reader) do |c|
            Shoko::Application::Adapters::SidebarStateReaderAdapter.new(c.resolve(:global_state))
          end
        end

        # Register library scanning services
        def register_library_services(container)
          container.register_singleton(:cached_library_repository) do |_c|
            Shoko::Adapters::Storage::Repositories::CachedLibraryRepository.new
          end
          container.register_factory(:library_scanner) { |c| Shoko::Adapters::BookSources::LibraryScanner.new(logger: c.resolve(:logger)) }
        end

        # Apply test mode configuration if available
        def apply_test_configuration(container)
          Shoko::TestSupport::TestMode.configure_container(container) if defined?(Shoko::TestSupport::TestMode)
        end

        public

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
          container.register(:epub_cache_factory, ->(path) { Shoko::Adapters::Storage::EpubCache.new(path) })
          container.register(:epub_cache_predicate, ->(path) { Shoko::Adapters::Storage::EpubCache.cache_file?(path) })
          container.register(:file_writer, Shoko::Adapters::Storage::FileWriterService.new(
            atomic_file_writer: container.resolve_optional(:atomic_file_writer)
          ))
          container.register(:instrumentation_service, Shoko::Adapters::Output::InstrumentationService.new)
          container.register(:instrumentation, container.resolve(:instrumentation_service))
          container.register(:text_metrics, Shoko::Adapters::Output::Terminal::TextMetrics)
          container.register(:display_capabilities, Shoko::Core::Services::DefaultDisplayCapabilities.new)
          container.register(:async_executor, Shoko::Core::Services::InlineExecutor.new)
          # New hexagonal ports for testing
          container.register(:config_storage, Shoko::Adapters::Storage::ConfigStorageAdapter.new)
          container.register(:terminal_capabilities, Shoko::Core::Services::DefaultTerminalCapabilities.new)
          container.register(:layout_metrics, Shoko::Core::Services::DefaultLayoutMetrics.new)
          container.register(:domain_event_bus, Shoko::Core::Events::DomainEventBus.new(container.resolve(:event_bus)))
          # Register test doubles for hexagonal port adapters
          container.register(:reader_state_reader, RSpec::Mocks::Double.new('ReaderStateReader',
                                                                            current_chapter: 0, total_chapters: 1,
                                                                            current_page_index: 0, left_page: 0,
                                                                            right_page: 0, single_page: 0,
                                                                            current_page: 0, page_map: [],
                                                                            book_path: nil, bookmarks: []))
          container.register(:ui_state_reader, RSpec::Mocks::Double.new('UIStateReader',
                                                                        terminal_width: 80, terminal_height: 24))
          container.register(:config_reader, RSpec::Mocks::Double.new('ConfigReader',
                                                                      page_numbering_mode: :dynamic,
                                                                      view_mode: :split, line_spacing: 1,
                                                                      dictionary_source_lang: nil,
                                                                      dictionary_target_lang: nil,
                                                                      dictionary_path: nil,
                                                                      dictionary_backend: nil))
          container.register(:state_writer, RSpec::Mocks::Double.new('StateWriter',
                                                                     update_pagination_state: nil,
                                                                     update_page: nil, update_selections: nil,
                                                                     update_ui_loading: nil, update_reader: nil,
                                                                     update_navigation: nil, update_bookmarks: nil))
          container.register(:render_state_writer, RSpec::Mocks::Double.new('RenderStateWriter',
                                                                            clear_rendered_lines: nil,
                                                                            update_rendered_lines: nil))
          container.register(:progress_state_reader, RSpec::Mocks::Double.new('ProgressStateReader',
                                                                               chapter_line_offset: nil,
                                                                               pending_progress: nil,
                                                                               pending_progress?: false))
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
