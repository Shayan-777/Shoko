# frozen_string_literal: true

require_relative 'internal/dynamic_layout_cache'
require_relative 'internal/layout_metrics_calculator'
require_relative 'internal/page_hydration_facade'
require_relative 'internal/page_hydrator'
require_relative 'internal/pagination_workflow'
require_relative 'internal/restore_mapping_service'
require_relative 'default_text_wrapper'
require_relative 'layout_resolver'
require_relative 'page_calculator_service/cached_layout_hydrator'
require_relative 'page_calculator_service/dynamic_layout_manager'
require_relative 'page_calculator_service/initialization_support'
require_relative '../../../core/models/reader_settings'
require_relative '../../../core/services/pagination/internal/absolute_page_map_builder'
require_relative '../../../core/services/null_logger'
require_relative '../../../application/ports/outbound/text_metrics'
require_relative '../../../application/ports/outbound/display_capabilities'
require_relative '../../../application/ports/outbound/instrumentation'
require_relative '../../../application/ports/outbound/line_wrapper'
require_relative '../../../application/ports/outbound/chapter_formatter'
require_relative '../../../application/ports/outbound/dynamic_page_source'

module Shoko
  module Application
    module Services
      module Pagination
        # Application pagination service that owns layout variants, cache orchestration, and hydration.
        class PageCalculatorService
          include Application::Ports::Outbound::DynamicPageSource
          include PageCalculatorInitializationSupport

          DYNAMIC_LAYOUT_CACHE_LIMIT = 8

          def initialize(text_metrics:, display_capabilities:, instrumentation:, config_reader:,
                         layout_service: nil, pagination_cache: nil, wrapping_service: nil,
                         formatting_service: nil, logger: nil)
            validate_optional_pagination_ports!(wrapping_service: wrapping_service,
                                                formatting_service: formatting_service)

            assign_dependencies(
              text_metrics: text_metrics,
              display_capabilities: display_capabilities,
              instrumentation: instrumentation,
              config_reader: config_reader,
              wrapping_service: wrapping_service,
              logger: logger
            )
            build_pagination_stack(
              layout_service: layout_service,
              pagination_cache: pagination_cache,
              wrapping_service: wrapping_service,
              formatting_service: formatting_service
            )
          end

          def pages_data
            @dynamic_layout_cache.pages_data
          end

          # Resets all session-specific state so the singleton is safe for reuse
          # across reader sessions. Must be called before a new book is opened.
          def reset_session!
            @dynamic_layout_cache.reset!
            @restore_mapping.reset!
            @doc_ref = nil
          end

          # Get page data by index, hydrating the page if formatted lines are needed.
          def get_page(page_index, width: nil, height: nil, sidebar_visible: nil)
            measure_with_instrumentation('page_map.hydrate') do
              @page_hydration.fetch(page_index, width: width, height: height, sidebar_visible: sidebar_visible)
            end
          end

          # Find the page index for the given chapter and line offset.
          def find_page_index(chapter_index, line_offset)
            @restore_mapping.find_page_index(chapter_index, line_offset)
          end

          # Total pages currently loaded in the active page map.
          def total_pages
            @dynamic_layout_cache.total_pages
          end

          # Build dynamic (lazy) page map and return sync payload for application orchestration.
          def build_dynamic_map!(width, height, doc, sidebar_visible:, **compat, &)
            ensure_config_reader!(compat)
            @dynamic_layout_manager.build_map(
              width: width,
              height: height,
              doc: doc,
              sidebar_visible: sidebar_visible,
              &
            )
          end

          # Switches dynamic pagination to a specific layout variant (base/sidebar)
          # and preserves reading position via line offset mapping.
          def switch_dynamic_layout_variant!(width, height, doc, sidebar_visible:, reader_state_reader:)
            @dynamic_layout_manager.switch_layout(
              width: width,
              height: height,
              doc: doc,
              sidebar_visible: sidebar_visible,
              reader_state_reader: reader_state_reader
            )
          end

          # Build absolute page map and return sync payload for application orchestration.
          def build_absolute_map!(width, height, doc, **compat, &)
            map = build_absolute_page_map(width, height, doc, **compat, &)
            @dynamic_layout_cache.remember_layout(width: width, height: height, sidebar_visible: false)
            {
              page_map: map,
              total_pages: map.sum,
              last_width: width,
              last_height: height,
            }
          end

          # Build the precise pending-restore payload (dynamic mode), if present.
          def apply_pending_precise_restore!(reader_state_reader)
            @restore_mapping.apply_pending_precise_restore!(reader_state_reader)
          rescue Shoko::Error => e
            logger.debug('apply_pending_precise_restore failed', error: e.message)
            nil
          end

          def resolve_document_reference
            # Document is intentionally late-bound: it changes during the app
            # lifecycle and isn't available when this singleton is first created.
            @doc_ref
          end

          # Hydrate from cached pagination without recomputation and return sync payload.
          def hydrate_from_cache(pages, width: nil, height: nil, sidebar_visible: false, doc: nil)
            return nil unless pages.is_a?(Array)

            @doc_ref = doc if doc
            @cached_layout_hydrator.hydrate(pages, width: width, height: height, sidebar_visible: sidebar_visible)
            {
              total_pages: total_pages,
              last_width: width,
              last_height: height,
            }
          end

          private

          attr_reader :logger

          def build_absolute_page_map(terminal_width, terminal_height, doc, **compat)
            ensure_config_reader!(compat)
            col_width, content_height = @metrics_calculator.layout(terminal_width, terminal_height)
            lines_per_page = @metrics_calculator.lines_per_page_for(content_height)

            Shoko::Core::Services::Pagination::Internal::AbsolutePageMapBuilder.build(
              doc,
              col_width,
              lines_per_page,
              @wrapping_service,
              text_metrics: @text_metrics
            ) do |done, total|
              yield(done, total) if block_given?
            end
          end

          def build_dynamic_pages(width, height, doc, sidebar_visible:, &on_progress)
            result = @pagination_workflow.build_dynamic(
              doc: doc,
              width: width,
              height: height,
              sidebar_visible: sidebar_visible,
              &on_progress
            )
            @doc_ref = doc
            result.pages
          end

          def ensure_config_reader!(compat)
            compat[:config_reader] || @config_reader || raise(ArgumentError, 'config_reader is required')
          end

          def validate_optional_pagination_ports!(wrapping_service:, formatting_service:)
            if wrapping_service && !wrapping_service.is_a?(Shoko::Application::Ports::Outbound::LineWrapper)
              raise ArgumentError, 'wrapping_service must implement Application::Ports::Outbound::LineWrapper'
            end
            unless formatting_service && !formatting_service.is_a?(Shoko::Application::Ports::Outbound::ChapterFormatter)
              return
            end

            raise ArgumentError, 'formatting_service must implement Application::Ports::Outbound::ChapterFormatter'
          end

          def measure_with_instrumentation(metric, &)
            @instrumentation.measure(metric, &)
          end
        end
      end
    end
  end
end
# NOTE: Former helper that prepopulated lines for cached pages has been
# removed to avoid blocking first paint. Lines are populated lazily in
# #get_page when needed.
