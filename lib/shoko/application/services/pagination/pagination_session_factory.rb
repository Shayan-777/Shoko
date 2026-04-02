# frozen_string_literal: true

require_relative 'layout_resolver'
require_relative 'pagination_session'
require_relative 'restore_manager'
require_relative 'session_state_sync'
require_relative '../../../adapters/output/null_display_capabilities'

module Shoko
  module Application
    module Services
      module Pagination
        # Builds fresh pagination sessions from current stores and runtime context.
        class PaginationSessionFactory
          def initialize(reader_runtime_context:, pagination_cache:, instrumentation:, logger: nil)
            @reader_runtime_context = reader_runtime_context
            @pagination_cache = pagination_cache
            @instrumentation = instrumentation
            @logger = logger
            @layout_resolver = PaginationLayoutResolver.new(
              display_capabilities: display_capabilities,
              pagination_cache: pagination_cache
            )
          end

          def build(doc:, page_calculator:, app_config_store:, reader_session_store:,
                    reader_view_state_store:, reader_pagination_store:, dimensions: nil)
            return nil unless doc && page_calculator

            config_snapshot = app_config_store.load
            state_sync = build_state_sync(reader_session_store, reader_view_state_store, reader_pagination_store)
            layout_spec = build_layout_spec(config_snapshot, dimensions, reader_view_state_store)
            build_session(
              doc: doc,
              page_calculator: page_calculator,
              config_snapshot: config_snapshot,
              layout_spec: layout_spec,
              state_sync: state_sync
            )
          end

          private

          def build_layout_spec(config_snapshot, dimensions, reader_view_state_store)
            width, height = dimensions || terminal_dimensions
            @layout_resolver.resolve(
              config_reader: config_snapshot,
              width: width,
              height: height,
              sidebar_visible: reader_view_state_store.sidebar_visible?
            )
          end

          def build_state_sync(reader_session_store, reader_view_state_store, reader_pagination_store)
            PaginationSessionStateSync.new(
              reader_session_snapshot: reader_session_store.load,
              reader_session_store: reader_session_store,
              reader_view_state_store: reader_view_state_store,
              reader_pagination_store: reader_pagination_store
            )
          end

          def build_session(doc:, page_calculator:, config_snapshot:, layout_spec:, state_sync:)
            PaginationSession.new(
              doc: doc,
              page_calculator: page_calculator,
              config_snapshot: config_snapshot,
              layout_spec: layout_spec,
              state_sync: state_sync,
              restore_manager: build_restore_manager(page_calculator:, state_sync:, layout_spec:),
              **runtime_dependencies
            )
          end

          def build_restore_manager(page_calculator:, state_sync:, layout_spec:)
            PaginationRestoreManager.new(
              page_calculator: page_calculator,
              state_sync: state_sync,
              layout_spec: layout_spec
            )
          end

          def runtime_dependencies
            {
              pagination_cache: @pagination_cache,
              display_capabilities: display_capabilities,
              instrumentation: @instrumentation,
              logger: @logger,
            }
          end

          def display_capabilities
            if @reader_runtime_context.respond_to?(:display_capabilities)
              return @reader_runtime_context.display_capabilities
            end

            @display_capabilities ||= Shoko::Adapters::Output::NullDisplayCapabilities.new
          end

          def terminal_dimensions
            size = @reader_runtime_context.terminal_size
            [size.width, size.height]
          end
        end
      end
    end
  end
end
