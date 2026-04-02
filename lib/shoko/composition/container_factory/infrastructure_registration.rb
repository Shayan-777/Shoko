# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      # Registers infrastructure/runtime services in the DI container.
      module InfrastructureRegistration
        def register_infrastructure(container, log_config = {})
          register_runtime_adapters(container)
          configure_text_metrics(container)
          register_monitoring_services(container, log_config)
          register_storage_services(container)
          register_epub_cache_factories(container)
          register_worker_factories(container)
          register_domain_event_bus(container)
        end

        private

        def register_runtime_adapters(container)
          register_runtime_environment(container)
          register_runtime_time_services(container)
          register_runtime_launch_state(container)
        end

        def register_runtime_environment(container)
          container.register_singleton(:runtime_config) do |_c|
            Shoko::Adapters::Runtime::EnvRuntimeConfigAdapter.new
          end
          container.register_singleton(:process_control) do |_c|
            Shoko::Adapters::Runtime::ProcessControlAdapter.new
          end
        end

        def register_runtime_time_services(container)
          container.register_singleton(:clock) do |_c|
            Shoko::Adapters::Runtime::MonotonicClockAdapter.new
          end
          container.register_singleton(:wall_clock) do |_c|
            Shoko::Adapters::Runtime::SystemWallClockAdapter.new
          end
          container.register_singleton(:id_generator) do |_c|
            Shoko::Adapters::Runtime::UuidGeneratorAdapter.new
          end
        end

        def register_runtime_launch_state(container)
          container.register_singleton(:reader_launch_state) do |_c|
            Shoko::Adapters::Runtime::SessionState::ReaderLaunchStateAdapter.new
          end
          container.register_singleton(:menu_launch_state) do |_c|
            Shoko::Adapters::Runtime::SessionState::MenuLaunchStateAdapter.new
          end
        end

        def configure_text_metrics(container)
          Shoko::Shared::Terminal::TextMetrics.configure_runtime_config!(
            runtime_config: container.resolve(:runtime_config)
          )
        end

        def register_monitoring_services(container, log_config)
          register_logger_bus_services(container, log_config)
          register_performance_services(container, log_config)
        end

        def register_logger_bus_services(container, log_config)
          container.register_singleton(:logger) do |_c|
            Shoko::Adapters::Monitoring::LoggerAdapter.new(level: log_config[:level], output: log_config[:output])
          end
          container.register_singleton(:event_bus) do |c|
            Shoko::Adapters::Runtime::SessionState::EventBus.new(logger: c.resolve(:logger))
          end
          container.register_singleton(:event_publisher) do |c|
            Shoko::Adapters::Runtime::SessionState::EventPublisherAdapter.new(event_bus: c.resolve(:event_bus))
          end
        end

        def register_performance_services(container, log_config)
          container.register_singleton(:performance_monitor) do |c|
            Shoko::Adapters::Monitoring::PerformanceMonitor.new(logger: c.resolve(:logger))
          end
          container.register_singleton(:perf_tracer) do |c|
            Shoko::Adapters::Monitoring::PerfTracer.new(
              profile_path: log_config[:profile_path],
              runtime_config: c.resolve(:runtime_config)
            )
          end
        end

        def register_storage_services(container)
          register_cache_storage_services(container)
          register_runtime_storage_services(container)
        end

        def register_cache_storage_services(container)
          container.register(:pagination_cache, Shoko::Adapters::Storage::PaginationCache)
          container.register(:cache_paths, Shoko::Adapters::Storage::CachePaths)
          container.register(:atomic_file_writer, Shoko::Adapters::Storage::AtomicFileWriter)
          container.register_singleton(:cache_pointer_resolver) do |_c|
            Shoko::Adapters::Storage::CachePointerResolver.new
          end
          container.register_singleton(:cache_availability) do |c|
            Shoko::Adapters::Storage::CacheAvailabilityAdapter.new(
              cache_root: c.resolve(:cache_paths).cache_root,
              logger: c.resolve(:logger),
              runtime_config: c.resolve(:runtime_config)
            )
          end
        end

        def register_runtime_storage_services(container)
          container.register_singleton(:recent_files_repository) do |c|
            Shoko::Adapters::Storage::RecentFilesRepository.new(
              recent_file_path: Shoko::Adapters::Storage::RecentFilesRepository.default_recent_file_path,
              atomic_file_writer: c.resolve(:atomic_file_writer),
              wall_clock: c.resolve(:wall_clock)
            )
          end
        end

        def register_domain_event_bus(container)
          event_bus = container.resolve(:event_bus)
          container.register_singleton(:domain_event_bus) do |c|
            Shoko::Core::Events::DomainEventBus.new(
              event_publisher: c.resolve(:event_publisher),
              logger: c.resolve(:logger)
            )
          end
          event_bus
        end

        def apply_runtime_configuration(container)
          runtime_config = container.resolve(:runtime_config)
          Shoko::Adapters::Runtime::REXMLSecurityLimitsAdapter.new(runtime_config: runtime_config).apply!
        end

        # Register cache factory lambdas
        def register_epub_cache_factories(container)
          register_cache_factories(container)
          register_book_source_clients(container)
        end

        def register_cache_factories(container)
          container.register_singleton(:epub_cache_factory) do |c|
            logger = c.resolve(:logger)
            runtime_config = c.resolve(:runtime_config)
            ->(path) { Shoko::Adapters::Storage::EpubCache.new(path, logger: logger, runtime_config: runtime_config) }
          end
          container.register(:epub_cache_predicate, ->(path) { Shoko::Adapters::Storage::EpubCache.cache_file?(path) })
        end

        def register_book_source_clients(container)
          container.register_singleton(:gutendex_client) do |c|
            require_relative '../../adapters/book_sources/gutendex_client'

            Shoko::Adapters::BookSources::GutendexClient.new(logger: c.resolve(:logger))
          end
          container.register_singleton(:libgen_client) do |c|
            require_relative '../../adapters/book_sources/libgen_client'

            Shoko::Adapters::BookSources::LibgenClient.new(
              base_url: c.resolve(:runtime_config).libgen_base_url,
              logger: c.resolve(:logger)
            )
          end
        end

        # Register background worker and parser factories
        def register_worker_factories(container)
          container.register_singleton(:background_worker_builder) do |_c|
            Shoko::Adapters::Storage::BackgroundWorkerBuilderAdapter.new
          end
          container.register_singleton(:xhtml_parser_factory) do |c|
            logger = c.resolve(:logger)
            lambda { |raw|
              require_relative '../../adapters/book_sources/epub/parser/xhtml_content_parser'

              Shoko::Adapters::BookSources::Epub::XHTMLContentParser.new(raw, logger: logger)
            }
          end
        end
      end
    end
  end
end
