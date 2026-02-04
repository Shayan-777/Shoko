# frozen_string_literal: true

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
require_relative '../adapters/storage/cache_pointer_resolver'
require_relative '../adapters/storage/cache_availability_adapter'
require_relative '../adapters/storage/recent_files_repository'
require_relative '../adapters/input/command_factory'
require_relative '../adapters/input/key_classifier_adapter'
require_relative '../adapters/output/terminal/text_sanitizer_adapter'
require_relative '../adapters/storage/dictionary_availability_adapter'
require_relative '../adapters/storage/cache_manager_adapter'
require_relative '../adapters/book_sources/epub/parsers/metadata_extractor'
require_relative '../adapters/book_sources/epub_finder'
require_relative '../adapters/book_sources/metadata_reader_adapter'
require_relative '../adapters/input/input_system_factory_adapter'
require_relative '../adapters/output/ui/rendering_factory_adapter'
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
require_relative 'adapters/menu_state_reader_adapter'
require_relative 'adapters/menu_state_writer_adapter'
require_relative 'adapters/notification_writer_adapter'
require_relative 'adapters/command_port_adapter'
require_relative 'adapters/wrapped_lines_provider_adapter'
require_relative 'ui/reader_view_model_builder'
require_relative '../adapters/output/ui/component_factory'

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

      # Remove a registered service instance
      #
      # @param name [Symbol] Service name
      def unregister(name)
        @services.delete(name)
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
        child.copy_registrations_from(self)
        child
      end

      # Clear all registrations (for testing)
      def clear!
        @services.clear
        @factories.clear
        @singletons.clear
      end

      # Copy registrations from another container
      # @api private
      def copy_registrations_from(source)
        @services = source.registry_services.dup
        @factories = source.registry_factories.dup
        @singletons = source.registry_singletons.dup
      end

      protected

      def registry_services = @services
      def registry_factories = @factories
      def registry_singletons = @singletons

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
        # @param log_config [Hash] Logger configuration from CLI
        #   :level [Symbol] Log level (:debug, :info, :warn, :error, :fatal)
        #   :output [IO] Output destination for log messages
        #   :profile_path [String, nil] Path for performance profiling output
        #   :debug [Boolean] Whether debug mode is active
        # @return [DependencyContainer]
        def create_default_container(log_config: {})
          container = DependencyContainer.new
          event_bus = register_infrastructure(container, log_config)
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
        def register_infrastructure(container, log_config = {})
          # Register logger first so other services can use it
          container.register_singleton(:logger) do |_c|
            Shoko::Adapters::Monitoring::LoggerAdapter.new(
              level: log_config[:level],
              output: log_config[:output]
            )
          end
          container.register_singleton(:event_bus) do |c|
            Shoko::Application::Infrastructure::EventBus.new(logger: c.resolve(:logger))
          end
          container.register_singleton(:performance_monitor) do |c|
            Shoko::Adapters::Monitoring::PerformanceMonitor.new(logger: c.resolve(:logger))
          end
          container.register_singleton(:perf_tracer) do |_c|
            Shoko::Adapters::Monitoring::PerfTracer.new(profile_path: log_config[:profile_path])
          end
          container.register(:pagination_cache, Shoko::Adapters::Storage::PaginationCache)
          container.register(:cache_paths, Shoko::Adapters::Storage::CachePaths)
          container.register(:atomic_file_writer, Shoko::Adapters::Storage::AtomicFileWriter)
          container.register_singleton(:cache_pointer_resolver) do |_c|
            Shoko::Adapters::Storage::CachePointerResolver.new
          end
          container.register_singleton(:cache_availability) do |c|
            Shoko::Adapters::Storage::CacheAvailabilityAdapter.new(
              cache_root: c.resolve(:cache_paths).cache_root,
              logger: c.resolve_optional(:logger)
            )
          end
          container.register_singleton(:recent_files_repository) do |_c|
            Shoko::Adapters::Storage::RecentFilesRepository.new
          end
          register_epub_cache_factories(container)
          register_worker_factories(container)

          # Domain event bus (capture event_bus early)
          event_bus = container.resolve(:event_bus)
          container.register_singleton(:domain_event_bus) do |c|
            Shoko::Core::Events::DomainEventBus.new(event_bus, logger: c.resolve(:logger))
          end
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
            executor = (c.resolve(:background_worker) if c.registered?(:background_worker))
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
          container.register_singleton(:key_classifier) do |_c|
            Shoko::Adapters::Input::KeyClassifierAdapter.new(
              command_factory: Shoko::Adapters::Input::CommandFactory
            )
          end
          container.register_singleton(:text_sanitizer) do |_c|
            Shoko::Adapters::Output::Terminal::TextSanitizerAdapter.new
          end
          container.register_singleton(:dictionary_availability) do |_c|
            Shoko::Adapters::Storage::DictionaryAvailabilityAdapter.new(
              backend_class: Shoko::Adapters::Storage::SqliteDictionaryAdapter
            )
          end
          container.register_singleton(:cache_manager) do |_c|
            Shoko::Adapters::Storage::CacheManagerAdapter.new(
              epub_cache_clearer: -> { Shoko::Adapters::BookSources::EPUBFinder.clear_cache },
              cache_path_provider: Shoko::Adapters::Storage::CachePaths
            )
          end
          container.register_singleton(:metadata_reader) do |_c|
            Shoko::Adapters::BookSources::MetadataReaderAdapter.new(
              extractor: Shoko::Adapters::BookSources::Epub::Parsers::MetadataExtractor
            )
          end
          container.register_singleton(:input_system_factory) do |_c|
            Shoko::Adapters::Input::InputSystemFactoryAdapter.new
          end
          container.register_singleton(:rendering_factory) do |_c|
            Shoko::Adapters::Output::Ui::RenderingFactoryAdapter.new
          end
        end

        # Register EPUB cache factory lambdas
        def register_epub_cache_factories(container)
          container.register_singleton(:epub_cache_factory) do |c|
            logger = c.resolve_optional(:logger)
            ->(path) { Shoko::Adapters::Storage::EpubCache.new(path, logger: logger) }
          end
          container.register(:epub_cache_predicate, ->(path) { Shoko::Adapters::Storage::EpubCache.cache_file?(path) })
          container.register_singleton(:gutendex_client) do |c|
            Shoko::Adapters::BookSources::GutendexClient.new(logger: c.resolve(:logger))
          end
        end

        # Register background worker and parser factories
        def register_worker_factories(container)
          container.register(:background_worker_factory, lambda { |logger:, name: 'shoko-worker'|
            Shoko::Adapters::Storage::BackgroundWorker.new(name: name, logger: logger)
          })
          container.register_singleton(:xhtml_parser_factory) do |c|
            logger = c.resolve_optional(:logger)
            lambda { |raw|
              Shoko::Adapters::BookSources::Epub::Parsers::XHTMLContentParser.new(raw, logger: logger)
            }
          end
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
          container.register_factory(:navigation_service) do |c|
            Shoko::Core::Services::NavigationService.new(
              config_reader: c.resolve(:config_reader),
              reader_state_reader: c.resolve(:reader_state_reader),
              ui_state_reader: c.resolve(:ui_state_reader),
              state_writer: c.resolve(:state_writer),
              page_calculator: c.resolve(:page_calculator),
              layout_service: c.resolve(:layout_service),
              wrapped_lines_provider: c.resolve_optional(:wrapped_lines_provider),
              display_capabilities: c.resolve_optional(:display_capabilities),
              logger: c.resolve_optional(:logger)
            )
          end
          container.register_factory(:bookmark_service) do |c|
            Shoko::Core::Services::BookmarkService.new(
              event_bus: c.resolve(:event_bus),
              bookmark_repository: c.resolve(:bookmark_repository),
              domain_event_bus: c.resolve(:domain_event_bus),
              config_reader: c.resolve(:config_reader),
              reader_state_reader: c.resolve(:reader_state_reader),
              ui_state_reader: c.resolve(:ui_state_reader),
              state_writer: c.resolve(:state_writer),
              page_calculator: c.resolve_optional(:page_calculator),
              layout_service: c.resolve_optional(:layout_service),
              terminal_service: c.resolve_optional(:terminal_service),
              logger: c.resolve_optional(:logger)
            )
          end
          container.register_singleton(:page_calculator) do |c|
            Shoko::Core::Services::PageCalculatorService.new(
              text_metrics: c.resolve(:text_metrics),
              display_capabilities: c.resolve(:display_capabilities),
              instrumentation: c.resolve(:instrumentation),
              config_reader: c.resolve(:config_reader),
              ui_state_reader: c.resolve(:ui_state_reader),
              layout_service: c.resolve_optional(:layout_service),
              pagination_cache: c.resolve_optional(:pagination_cache),
              wrapping_service: c.resolve_optional(:wrapping_service),
              formatting_service: c.resolve_optional(:formatting_service),
              logger: c.resolve_optional(:logger)
            )
          end
          container.register_factory(:coordinate_service) do |c|
            Shoko::Core::Services::CoordinateService.new(
              terminal_service: c.resolve_optional(:terminal_service),
              logger: c.resolve_optional(:logger)
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
          container.register_factory(:annotation_service) do |c|
            Shoko::Core::Services::AnnotationService.new(
              annotation_repository: c.resolve(:annotation_repository),
              domain_event_bus: c.resolve(:domain_event_bus),
              state_writer: c.resolve(:state_writer),
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
          container.register_singleton(:wrapped_lines_provider) do |c|
            Shoko::Application::Adapters::WrappedLinesProviderAdapter.new(
              formatting_service: c.resolve_optional(:formatting_service),
              document: c.resolve_optional(:document)
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
              logger: c.resolve_optional(:logger)
            )
          end
          container.register_singleton(:ui_component_factory) do |_c|
            color_mode = begin
              Shoko::Adapters::Output::Terminal::Terminal.color_mode
            rescue StandardError
              :dark
            end
            Shoko::Adapters::Output::Ui::ComponentFactory.new(color_mode: color_mode)
          end
          container.register_singleton(:render_registry) { |_c| Shoko::Adapters::Output::RenderRegistry.new }
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
              logger: c.resolve_optional(:logger)
            )
          end
          container.register_factory(:download_service) do |c|
            Shoko::Adapters::BookSources::DownloadService.new(
              gutendex_client: c.resolve(:gutendex_client),
              logger: c.resolve_optional(:logger)
            )
          end
          container.register_factory(:settings_service) do |c|
            Shoko::Application::UseCases::SettingsService.new(
              state_store: c.resolve(:state_store),
              terminal_service: c.resolve(:terminal_service),
              cache_manager: c.resolve(:cache_manager),
              dictionary_availability: c.resolve(:dictionary_availability),
              wrapping_service: c.resolve_optional(:wrapping_service),
              recent_files_repository: c.resolve_optional(:recent_files_repository),
              dictionary_service: c.resolve_optional(:dictionary_service),
              catalog_service: c.resolve_optional(:catalog_service),
              logger: c.resolve_optional(:logger)
            )
          end
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
          instrumentation = container.resolve_optional(:instrumentation_service)
          Shoko::Adapters::BookSources::DocumentService.new(
            path, wrapper,
            formatting_service: formatting,
            background_worker: worker,
            progress_reporter: progress_reporter,
            logger: logger,
            instrumentation: instrumentation
          )
        end

        # Register state management services
        def register_state_management(container, event_bus)
          container.register_singleton(:global_state) do |c|
            Shoko::Application::Infrastructure::ObserverStateStore.new(
              event_bus,
              config_storage: c.resolve(:config_storage),
              terminal_capabilities: c.resolve(:terminal_capabilities),
              logger: c.resolve_optional(:logger)
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
            Shoko::Application::Adapters::RenderedContentReaderAdapter.new(
              c.resolve(:global_state),
              render_registry: c.resolve(:render_registry)
            )
          end
          container.register_factory(:reader_state_reader) do |c|
            Shoko::Application::Adapters::ReaderStateReaderAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:ui_state_reader) do |c|
            Shoko::Application::Adapters::UIStateReaderAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:render_state_writer) do |c|
            Shoko::Application::Adapters::RenderStateWriterAdapter.new(
              c.resolve(:global_state),
              render_registry: c.resolve(:render_registry),
              logger: c.resolve(:logger)
            )
          end
          container.register_factory(:progress_state_reader) do |c|
            Shoko::Application::Adapters::ProgressStateReaderAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:sidebar_state_reader) do |c|
            Shoko::Application::Adapters::SidebarStateReaderAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:menu_state_reader) do |c|
            Shoko::Application::Adapters::MenuStateReaderAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:menu_state_writer) do |c|
            Shoko::Application::Adapters::MenuStateWriterAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:notification_writer) do |c|
            Shoko::Application::Adapters::NotificationWriterAdapter.new(
              c.resolve(:global_state),
              text_sanitizer: c.resolve_optional(:text_sanitizer)
            )
          end
          container.register_singleton(:command_port) do |_c|
            Shoko::Application::Adapters::CommandPortAdapter.new
          end
          container.register_factory(:view_model_builder_factory) do |c|
            state = c.resolve(:global_state)
            lambda { |doc|
              Shoko::Application::UI::ReaderViewModelBuilder.new(state, doc)
            }
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

        # Build a fully-wired MouseableReader controller.
        # This is the sole composition point for the reader — all .resolve() calls
        # happen here, and the controller itself never touches the container.
        def build_reader_controller(container, epub_path)
          c = container
          input_system_factory = c.resolve(:input_system_factory)
          Shoko::Application::Controllers::MouseableReader.new(
            epub_path,
            container: c,
            state: c.resolve(:global_state),
            terminal_service: c.resolve(:terminal_service),
            page_calculator: c.resolve(:page_calculator),
            clipboard_service: c.resolve(:clipboard_service),
            instrumentation: c.resolve_optional(:instrumentation),
            navigation_service: c.resolve_optional(:navigation_service),
            bookmark_service: c.resolve_optional(:bookmark_service),
            key_classifier: c.resolve_optional(:key_classifier),
            selection_service: c.resolve_optional(:selection_service),
            wrapping_service: c.resolve_optional(:wrapping_service),
            rendered_content_reader: c.resolve_optional(:rendered_content_reader),
            annotation_service: c.resolve_optional(:annotation_service),
            render_registry: c.resolve_optional(:render_registry),
            document_service_factory: c.resolve_optional(:document_service_factory),
            coordinate_service: c.resolve_optional(:coordinate_service),
            layout_service: c.resolve(:layout_service),
            rendering_factory: c.resolve(:rendering_factory),
            input_system_factory: input_system_factory,
            notification_service: c.resolve_optional(:notification_service),
            ui_component_factory: c.resolve_optional(:ui_component_factory),
            layout_metrics: c.resolve_optional(:layout_metrics),
            dictionary_service: c.resolve_optional(:dictionary_service),
            settings_service: c.resolve_optional(:settings_service),
            dictionary_availability: c.resolve_optional(:dictionary_availability),
            background_worker: c.resolve_optional(:background_worker),
            background_worker_factory: c.resolve_optional(:background_worker_factory),
            progress_repository: c.resolve_optional(:progress_repository),
            bookmark_repository: c.resolve_optional(:bookmark_repository),
            pagination_cache: c.resolve_optional(:pagination_cache),
            notification_writer: c.resolve_optional(:notification_writer),
            async_executor: c.resolve_optional(:async_executor),
            display_capabilities: c.resolve_optional(:display_capabilities),
            config_reader: c.resolve(:config_reader),
            reader_state_reader: c.resolve(:reader_state_reader),
            state_writer: c.resolve(:state_writer),
            instrumentation_service: c.resolve_optional(:instrumentation_service),
            pagination_cache_preloader: c.resolve_optional(:pagination_cache_preloader),
            render_state_writer: c.resolve_optional(:render_state_writer),
            mouse_handler: input_system_factory.create_mouse_handler,
            logger: c.resolve_optional(:logger),
            document: c.resolve_optional(:document)
          )
        end

        # Build a fully-wired MenuController.
        # This is the sole composition point for the menu.
        def build_menu_controller(container)
          c = container
          rendering_factory = c.resolve(:rendering_factory)

          Shoko::Application::Controllers::MenuController.new(
            container: c,
            state: c.resolve(:global_state),
            catalog: c.resolve(:catalog_service),
            terminal_service: c.resolve(:terminal_service),
            frame_coordinator: rendering_factory.create_frame_coordinator(c),
            render_pipeline: rendering_factory.create_render_pipeline(c),
            ui_component_factory: c.resolve(:ui_component_factory),
            key_classifier: c.resolve(:key_classifier),
            input_system_factory: c.resolve(:input_system_factory),
            notification_service: c.resolve_optional(:notification_service),
            settings_service: c.resolve_optional(:settings_service),
            annotation_service: c.resolve_optional(:annotation_service),
            logger: c.resolve_optional(:logger),
            pagination_cache: c.resolve_optional(:pagination_cache),
            display_capabilities: c.resolve_optional(:display_capabilities),
            instrumentation: c.resolve_optional(:instrumentation),
            download_service: c.resolve_optional(:download_service),
            dictionary_catalog_service: c.resolve_optional(:dictionary_catalog_service),
            text_sanitizer: c.resolve_optional(:text_sanitizer),
            background_worker_factory: c.resolve_optional(:background_worker_factory),
            recent_files_repository: c.resolve_optional(:recent_files_repository),
            cache_pointer_resolver: c.resolve_optional(:cache_pointer_resolver),
            dictionary_availability: c.resolve_optional(:dictionary_availability),
            page_calculator: c.resolve_optional(:page_calculator),
            layout_service: c.resolve_optional(:layout_service),
            wrapping_service: c.resolve_optional(:wrapping_service),
            document_service_factory: c.resolve_optional(:document_service_factory),
            config_reader: c.resolve_optional(:config_reader),
            reader_state_reader: c.resolve_optional(:reader_state_reader),
            state_writer: c.resolve_optional(:state_writer),
            pagination_cache_preloader: c.resolve_optional(:pagination_cache_preloader),
            document: c.resolve_optional(:document)
          )
        end

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
          container.register(:cache_pointer_resolver, Shoko::Adapters::Storage::CachePointerResolver.new)
          container.register(:cache_availability,
                             Shoko::Adapters::Storage::CacheAvailabilityAdapter.new(
                               cache_root: Shoko::Adapters::Storage::CachePaths.cache_root,
                               logger: container.resolve(:logger)
                             ))
          container.register(:recent_files_repository, Shoko::Adapters::Storage::RecentFilesRepository.new)
          test_logger = container.resolve(:logger)
          container.register(:epub_cache_factory, lambda { |path|
            Shoko::Adapters::Storage::EpubCache.new(path, logger: test_logger)
          })
          container.register(:epub_cache_predicate, ->(path) { Shoko::Adapters::Storage::EpubCache.cache_file?(path) })
          container.register(:xhtml_parser_factory, lambda { |raw|
            Shoko::Adapters::BookSources::Epub::Parsers::XHTMLContentParser.new(raw, logger: test_logger)
          })
          container.register(:file_writer, Shoko::Adapters::Storage::FileWriterService.new(
                                             atomic_file_writer: container.resolve_optional(:atomic_file_writer)
                                           ))
          container.register(:performance_monitor,
                             Shoko::Adapters::Monitoring::PerformanceMonitor.new(logger: test_logger))
          container.register(:perf_tracer, Shoko::Adapters::Monitoring::PerfTracer.new)
          container.register(:instrumentation_service, Shoko::Adapters::Output::InstrumentationService.new(
                                                         performance_monitor: container.resolve(:performance_monitor),
                                                         perf_tracer: container.resolve(:perf_tracer),
                                                         logger: test_logger
                                                       ))
          container.register(:instrumentation, container.resolve(:instrumentation_service))
          container.register(:text_metrics, Shoko::Adapters::Output::Terminal::TextMetrics)
          container.register(:display_capabilities, Shoko::Core::Services::DefaultDisplayCapabilities.new)
          container.register(:async_executor, Shoko::Core::Services::InlineExecutor.new)
          container.register(:wrapped_lines_provider, Shoko::Application::Adapters::WrappedLinesProviderAdapter.new)
          container.register(:ui_component_factory,
                             Shoko::Adapters::Output::Ui::ComponentFactory.new(color_mode: :dark))
          container.register(:config_storage, Shoko::Adapters::Storage::ConfigStorageAdapter.new)
          container.register(:terminal_capabilities, Shoko::Core::Services::DefaultTerminalCapabilities.new)
          container.register(:layout_metrics, Shoko::Core::Services::DefaultLayoutMetrics.new)
          container.register(:domain_event_bus, Shoko::Core::Events::DomainEventBus.new(
                                                  container.resolve(:event_bus),
                                                  logger: container.resolve(:logger)
                                                ))
          container.register(:key_classifier, Shoko::Adapters::Input::KeyClassifierAdapter.new(
                                                command_factory: Shoko::Adapters::Input::CommandFactory
                                              ))
          container.register(:text_sanitizer, Shoko::Adapters::Output::Terminal::TextSanitizerAdapter.new)
          container.register(:dictionary_availability, Shoko::Adapters::Storage::DictionaryAvailabilityAdapter.new(
                                                         backend_class: Shoko::Adapters::Storage::SqliteDictionaryAdapter
                                                       ))
          container.register(:cache_manager, Shoko::Adapters::Storage::CacheManagerAdapter.new(
                                               epub_cache_clearer: lambda {
                                                 Shoko::Adapters::BookSources::EPUBFinder.clear_cache
                                               },
                                               cache_path_provider: Shoko::Adapters::Storage::CachePaths
                                             ))
          container.register(:metadata_reader, Shoko::Adapters::BookSources::MetadataReaderAdapter.new(
                                                 extractor: Shoko::Adapters::BookSources::Epub::Parsers::MetadataExtractor
                                               ))
          container.register(:input_system_factory, Shoko::Adapters::Input::InputSystemFactoryAdapter.new)
          container.register(:rendering_factory, Shoko::Adapters::Output::Ui::RenderingFactoryAdapter.new)
          container.register(:render_registry, Shoko::Adapters::Output::RenderRegistry.new)
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
                                                                      view_mode: :single, line_spacing: :normal,
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
