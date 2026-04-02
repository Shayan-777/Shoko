# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        # Builder helpers for PageCalculatorService dependency wiring.
        module PageCalculatorInitializationSupport
          private

          def assign_dependencies(text_metrics:, display_capabilities:, instrumentation:, config_reader:,
                                  wrapping_service:, logger:)
            @logger = logger || Shoko::Core::Services::NullLogger.new
            @text_metrics = text_metrics
            @display_capabilities = display_capabilities
            @instrumentation = instrumentation
            @config_reader = config_reader
            @wrapping_service = wrapping_service
          end

          def build_pagination_stack(layout_service:, pagination_cache:, wrapping_service:, formatting_service:)
            build_runtime_helpers(
              layout_service: layout_service,
              pagination_cache: pagination_cache,
              wrapping_service: wrapping_service,
              formatting_service: formatting_service
            )
            build_page_services
          end

          def build_runtime_helpers(layout_service:, pagination_cache:, wrapping_service:, formatting_service:)
            @text_wrapper = DefaultTextWrapper.new(text_metrics: @text_metrics)
            @metrics_calculator = build_metrics_calculator(layout_service)
            @layout_resolver = build_layout_resolver(pagination_cache)
            @pagination_workflow = build_pagination_workflow(
              pagination_cache: pagination_cache,
              wrapping_service: wrapping_service,
              formatting_service: formatting_service
            )
            @page_hydrator = build_page_hydrator(
              wrapping_service: wrapping_service,
              formatting_service: formatting_service
            )
          end

          def build_layout_resolver(pagination_cache)
            @pagination_cache = pagination_cache
            PaginationLayoutResolver.new(
              display_capabilities: @display_capabilities,
              pagination_cache: pagination_cache
            )
          end

          def build_page_services
            @dynamic_layout_cache = Pagination::Internal::DynamicLayoutCache.new(
              cache_limit: self.class::DYNAMIC_LAYOUT_CACHE_LIMIT
            )
            @restore_mapping = Pagination::Internal::RestoreMappingService.new
            @dynamic_layout_manager = build_dynamic_layout_manager
            @cached_layout_hydrator = build_cached_layout_hydrator
            @page_hydration = build_page_hydration_facade
          end

          def build_metrics_calculator(layout_service)
            Pagination::Internal::LayoutMetricsCalculator.new(
              config_reader: @config_reader,
              layout_service: layout_service
            )
          end

          def build_pagination_workflow(pagination_cache:, wrapping_service:, formatting_service:)
            Pagination::Internal::PaginationWorkflow.new(
              metrics_calculator: @metrics_calculator,
              pagination_cache: pagination_cache,
              layout_resolver: @layout_resolver,
              text_metrics: @text_metrics,
              display_capabilities: @display_capabilities,
              instrumentation: @instrumentation,
              config_reader: @config_reader,
              line_wrapper: wrapping_service,
              chapter_formatter: formatting_service
            )
          end

          def build_page_hydrator(wrapping_service:, formatting_service:)
            Pagination::Internal::PageHydrator.new(
              text_wrapper: @text_wrapper,
              metrics_calculator: @metrics_calculator,
              config_reader: @config_reader,
              line_wrapper: wrapping_service,
              chapter_formatter: formatting_service
            )
          end

          def build_page_hydration_facade
            Pagination::Internal::PageHydrationFacade.new(
              page_hydrator: @page_hydrator,
              pages_reader: -> { @dynamic_layout_cache.pages_data },
              page_writer: ->(page_index, page) { @dynamic_layout_cache.replace_page(page_index, page) },
              document_reader: -> { resolve_document_reference },
              layout_context_reader: method(:layout_context),
              logger: @logger
            )
          end

          def build_dynamic_layout_manager
            Pagination::DynamicLayoutManager.new(
              dynamic_layout_cache: @dynamic_layout_cache,
              restore_mapping: @restore_mapping,
              config_reader: @config_reader,
              layout_resolver: @layout_resolver,
              logger: @logger,
              dynamic_page_builder: lambda do |width:, height:, doc:, sidebar_visible:, progress:|
                build_dynamic_pages(width, height, doc, sidebar_visible: sidebar_visible, &progress)
              end
            )
          end

          def build_cached_layout_hydrator
            Pagination::CachedLayoutHydrator.new(
              dynamic_layout_cache: @dynamic_layout_cache,
              restore_mapping: @restore_mapping,
              config_reader: @config_reader,
              layout_resolver: @layout_resolver
            )
          end

          def layout_context(width:, height:, sidebar_visible:)
            @dynamic_layout_cache.layout_context(width: width, height: height, sidebar_visible: sidebar_visible)
          end
        end
      end
    end
  end
end
