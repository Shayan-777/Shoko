# frozen_string_literal: true

module Shoko
  module Application
    module Composition
      module ContainerFactory
        # Registers infrastructure/runtime services in the DI container.
        module InfrastructureRegistration
          def register_infrastructure(container, log_config = {})
            container.register_singleton(:runtime_config) do |_c|
              Shoko::Adapters::Runtime::EnvRuntimeConfigAdapter.new
            end
            container.register_singleton(:reader_session_context) do |_c|
              Shoko::Application::Composition::ReaderSessionContext.new
            end
            container.register_singleton(:menu_session_context) do |_c|
              Shoko::Application::Composition::MenuSessionContext.new
            end

            # Register logger first so other services can use it
            container.register_singleton(:logger) do |_c|
              Shoko::Adapters::Monitoring::LoggerAdapter.new(
                level: log_config[:level],
                output: log_config[:output]
              )
            end
            container.register_singleton(:event_bus) do |c|
              Shoko::Adapters::State::EventBus.new(logger: c.resolve(:logger))
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

          def apply_runtime_configuration(container)
            runtime_config = container.resolve_optional(:runtime_config)
            Shoko::Adapters::Runtime::REXMLSecurityLimitsAdapter.new(
              runtime_config: runtime_config
            ).apply!
          end

          # Register cache factory lambdas
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
                Shoko::Core::BookFormats::Epub::XHTMLContentParser.new(raw, logger: logger)
              }
            end
          end
        end
      end
    end
  end
end
