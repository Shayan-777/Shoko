# frozen_string_literal: true

require_relative '../adapters/storage/background_worker'
require_relative '../adapters/storage/atomic_file_writer'
require_relative '../adapters/monitoring/performance_monitor'
require_relative '../adapters/monitoring/perf_tracer'
require_relative '../adapters/storage/pagination_cache'
require_relative '../adapters/storage/cache_paths'
require_relative '../adapters/storage/epub_cache'
require_relative '../adapters/output/kitty/kitty_image_renderer'
require_relative '../adapters/book_sources/gutendex_client'
require_relative '../adapters/storage/repositories/cached_library_repository'
require_relative '../adapters/book_sources/epub/parsers/xhtml_content_parser'
require_relative '../adapters/output/render_registry'
require_relative '../core/events/domain_event_bus'
require_relative '../adapters/storage/file_writer_service'
require_relative '../adapters/output/instrumentation_service'
require_relative '../adapters/book_sources/download_service'
require_relative 'adapters/config_reader_adapter'
require_relative 'adapters/state_writer_adapter'
require_relative 'adapters/rendered_content_reader_adapter'

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
          container.register_singleton(:event_bus) { Shoko::Application::Infrastructure::EventBus.new }
          container.register_singleton(:logger) { Shoko::Adapters::Monitoring::Logger }
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
          container.register(:background_worker_factory, lambda { |name: 'shoko-worker'|
            Shoko::Adapters::Storage::BackgroundWorker.new(name:)
          })
          container.register(:xhtml_parser_factory, lambda { |raw|
            Shoko::Adapters::BookSources::Epub::Parsers::XHTMLContentParser.new(raw)
          })
        end

        # Register repository implementations
        def register_repositories(container)
          container.register_factory(:bookmark_repository) { |c| Shoko::Adapters::Storage::Repositories::BookmarkRepository.new(c) }
          container.register_factory(:annotation_repository) { |c| Shoko::Adapters::Storage::Repositories::AnnotationRepository.new(c) }
          container.register_factory(:progress_repository) { |c| Shoko::Adapters::Storage::Repositories::ProgressRepository.new(c) }
          container.register_factory(:config_repository) { |c| Shoko::Adapters::Storage::Repositories::ConfigRepository.new(c) }
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
        end

        # Register application-level services and adapters
        def register_application_services(container)
          register_output_services(container)
          register_use_case_services(container)
          register_document_factory(container)
        end

        # Register output/rendering services
        def register_output_services(container)
          container.register_factory(:clipboard_service) { |c| Shoko::Adapters::Output::Clipboard::ClipboardService.new(c) }
          container.register_singleton(:terminal_service) { |c| Shoko::Adapters::Output::Terminal::TerminalService.new(c) }
          container.register_singleton(:wrapping_service) { |c| Shoko::Adapters::Output::Formatting::WrappingService.new(c) }
          container.register_singleton(:formatting_service) { |c| Shoko::Adapters::Output::Formatting::FormattingService.new(c) }
          container.register_singleton(:kitty_image_renderer) { |_c| Shoko::Adapters::Output::Kitty::KittyImageRenderer.new }
          container.register_singleton(:file_writer) { |c| Shoko::Adapters::Storage::FileWriterService.new(c) }
          container.register_singleton(:instrumentation_service) { |c| Shoko::Adapters::Output::InstrumentationService.new(c) }
          container.register_singleton(:notification_service) { |c| Shoko::Adapters::Output::NotificationService.new(c) }
          container.register_singleton(:render_registry) { |_c| Shoko::Adapters::Output::RenderRegistry.current }
        end

        # Register use case services
        def register_use_case_services(container)
          container.register_factory(:catalog_service) { |c| Shoko::Application::UseCases::CatalogService.new(c) }
          container.register_factory(:download_service) { |c| Shoko::Adapters::BookSources::DownloadService.new(c) }
          container.register_factory(:settings_service) { |c| Shoko::Application::UseCases::SettingsService.new(c) }
          container.register_factory(:pagination_cache_preloader) do |c|
            Shoko::Core::Services::Pagination::PaginationCachePreloader.new(
              state: c.resolve(:global_state),
              page_calculator: c.resolve(:page_calculator),
              pagination_cache: c.resolve(:pagination_cache),
              config_reader: c.resolve(:config_reader),
              state_writer: c.resolve(:state_writer)
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
          instantiate_document_service(
            Shoko::Adapters::BookSources::DocumentService,
            path, wrapper, formatting, worker, progress_reporter
          )
        end

        # Register state management services
        def register_state_management(container, event_bus)
          container.register_singleton(:global_state) { |_c| Shoko::Application::Infrastructure::ObserverStateStore.new(event_bus) }
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
        end

        # Register library scanning services
        def register_library_services(container)
          container.register_singleton(:cached_library_repository) do |_c|
            Shoko::Adapters::Storage::Repositories::CachedLibraryRepository.new
          end
          container.register_factory(:library_scanner) { |_c| Shoko::Adapters::BookSources::LibraryScanner.new }
        end

        # Apply test mode configuration if available
        def apply_test_configuration(container)
          Shoko::TestSupport::TestMode.configure_container(container) if defined?(Shoko::TestSupport::TestMode)
        end

        # Instantiate document service with fallback for different signatures
        def instantiate_document_service(klass, path, wrapper, formatting, worker, progress_reporter = nil)
          try_full_instantiation(klass, path, wrapper, formatting, worker, progress_reporter) ||
            try_without_worker(klass, path, wrapper, formatting, progress_reporter) ||
            try_minimal(klass, path, wrapper, progress_reporter) ||
            klass.new(path)
        end

        def try_full_instantiation(klass, path, wrapper, formatting, worker, progress_reporter)
          klass.new(path, wrapper, formatting_service: formatting, background_worker: worker,
                                   progress_reporter: progress_reporter)
        rescue ArgumentError
          nil
        end

        def try_without_worker(klass, path, wrapper, formatting, progress_reporter)
          klass.new(path, wrapper, formatting_service: formatting, progress_reporter: progress_reporter)
        rescue ArgumentError
          nil
        end

        def try_minimal(klass, path, wrapper, progress_reporter)
          klass.new(path, wrapper, progress_reporter: progress_reporter)
        rescue ArgumentError
          nil
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
          container.register(:logger, RSpec::Mocks::Double.new('Logger', info: nil, error: nil, debug: nil))
        end

        def register_test_infrastructure(container)
          container.register(:atomic_file_writer, Shoko::Adapters::Storage::AtomicFileWriter)
          container.register(:cache_paths, Shoko::Adapters::Storage::CachePaths)
          container.register(:epub_cache_factory, ->(path) { Shoko::Adapters::Storage::EpubCache.new(path) })
          container.register(:epub_cache_predicate, ->(path) { Shoko::Adapters::Storage::EpubCache.cache_file?(path) })
          container.register(:file_writer, Shoko::Adapters::Storage::FileWriterService.new(container))
          container.register(:instrumentation_service, Shoko::Adapters::Output::InstrumentationService.new(container))
          container.register(:domain_event_bus, Shoko::Core::Events::DomainEventBus.new(container.resolve(:event_bus)))
        end
      end
    end
  end
end
