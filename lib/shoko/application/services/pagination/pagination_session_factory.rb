# frozen_string_literal: true

require_relative 'pagination_layout_resolver'
require_relative 'pagination_layout_spec'
require_relative 'pagination_session'
require_relative 'restore_manager'
require_relative 'session_state_sync'
require 'shoko/application/ports/outbound/reader_runtime_context'

module Shoko
  module Application
    module Services
      module Pagination
        # Builds fresh pagination sessions from current stores and runtime context.
        class PaginationSessionFactory
          def initialize(reader_runtime_context:, pagination_cache:, instrumentation:, logger: nil)
            unless reader_runtime_context.is_a?(Shoko::Application::Ports::Outbound::ReaderRuntimeContext)
              raise ArgumentError, 'reader_runtime_context must implement Application::Ports::Outbound::ReaderRuntimeContext'
            end

            @reader_runtime_context = reader_runtime_context
            @pagination_cache = pagination_cache
            @instrumentation = instrumentation
            @logger = logger
          end

          def build(doc:, page_calculator:, app_config_store:, reader_session_store:,
                    reader_view_state_store:, reader_pagination_store:, dimensions: nil)
            return nil unless doc && page_calculator

            config_snapshot = app_config_store.load
            display_capabilities = @reader_runtime_context.display_capabilities
            build_session(
              **session_attributes(
                doc: doc,
                page_calculator: page_calculator,
                config_snapshot: config_snapshot,
                dimensions: dimensions,
                reader_session_store: reader_session_store,
                reader_view_state_store: reader_view_state_store,
                reader_pagination_store: reader_pagination_store,
                display_capabilities: display_capabilities
              )
            )
          end

          private

          def session_attributes(doc:, page_calculator:, config_snapshot:, dimensions:, reader_session_store:,
                                 reader_view_state_store:, reader_pagination_store:, display_capabilities:)
            state_sync = build_state_sync(reader_session_store, reader_view_state_store, reader_pagination_store)
            {
              doc: doc,
              page_calculator: page_calculator,
              config_snapshot: config_snapshot,
              layout_spec: build_layout_spec(config_snapshot, dimensions, display_capabilities),
              state_sync: state_sync,
              display_capabilities: display_capabilities,
            }
          end

          def build_layout_spec(config_snapshot, dimensions, display_capabilities)
            width, height = dimensions || terminal_dimensions
            build_layout_resolver(display_capabilities).resolve(
              config_reader: config_snapshot,
              width: width,
              height: height
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

          def build_session(doc:, page_calculator:, config_snapshot:, layout_spec:, state_sync:, display_capabilities:)
            PaginationSession.new(
              doc: doc,
              page_calculator: page_calculator,
              config_snapshot: config_snapshot,
              layout_spec: layout_spec,
              state_sync: state_sync,
              restore_manager: build_restore_manager(page_calculator:, state_sync:, layout_spec:),
              **runtime_dependencies(display_capabilities)
            )
          end

          def build_restore_manager(page_calculator:, state_sync:, layout_spec:)
            PaginationRestoreManager.new(
              page_calculator: page_calculator,
              state_sync: state_sync,
              layout_spec: layout_spec
            )
          end

          def runtime_dependencies(display_capabilities)
            {
              pagination_cache: @pagination_cache,
              display_capabilities: display_capabilities,
              instrumentation: @instrumentation,
              logger: @logger,
            }
          end

          def build_layout_resolver(display_capabilities)
            PaginationLayoutResolver.new(
              display_capabilities: display_capabilities,
              pagination_cache: @pagination_cache
            )
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
