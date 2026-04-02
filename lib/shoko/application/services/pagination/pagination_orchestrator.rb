# frozen_string_literal: true

require_relative 'pagination_orchestrator/loading_state_support'
require_relative 'pagination_runtime'
require_relative '../../../core/ports/outbound/reader_session_store'
require_relative '../../../core/ports/outbound/app_config_store'
require_relative '../../../core/ports/outbound/reader_runtime_context'
require_relative '../../../core/services/progress_helper'

module Shoko
  module Application
    module Services
      module Pagination
        # Handles pagination builds (dynamic/absolute) and progress overlay.
        # Keeps heavy orchestration out of ReaderController while preserving behavior.
        #
        # This class follows hexagonal architecture principles:
        # - Reader session/pagination/view state flow through focused stores
        # - Config flows through AppConfigStore
        # - Runtime sizing/display flows through ReaderRuntimeContext
        class PaginationOrchestrator
          # Factory for selecting per-mode pagination strategies.
          module StrategyFactory
            module_function

            def select(session)
              mode = session.config_snapshot.page_numbering_mode
              mode == :dynamic ? DynamicStrategy : AbsoluteStrategy
            end
          end

          # Base strategy type for pagination operations.
          class Strategy
            def initialize(session)
              @session = session
            end

            private

            attr_reader :session
          end

          # Dynamic pagination behavior.
          class DynamicStrategy < Strategy
            def build_full_map(progress: nil)
              session.build_dynamic_map(progress: progress)
              nil
            end

            def build_initial_map(progress:)
              build_full_map(progress: progress)
            end

            def refresh_after_resize
              session.build_dynamic_map
              session.clamp_dynamic_index!
            end

            def rebuild_after_config_change
              payload = session.pending_progress_payload
              session.update_reader(pending_progress: payload)
              session.build_dynamic_map
              session.clamp_dynamic_index!
            end

            def rebuild_dynamic(progress:)
              payload = session.pending_progress_payload
              session.with_loading('Rebuilding pagination…') do
                session.update_reader(pending_progress: payload)
                session.build_dynamic_map(progress: progress)
              end
              :handled
            end
          end

          # Absolute pagination behavior.
          class AbsoluteStrategy < Strategy
            def build_full_map(progress: nil)
              session.build_absolute_map(progress: progress)
            end

            def build_initial_map(progress:)
              build_full_map(progress: progress)
            end

            def refresh_after_resize
              session.build_absolute_map
            end

            def rebuild_after_config_change
              session.build_absolute_map
            end

            def rebuild_dynamic(progress: nil) # rubocop:disable Lint/UnusedMethodArgument
              :pass
            end
          end

          # Aggregates pagination inputs and exposes a per-document session API.
          # Uses focused reader stores/runtime context - no direct state access.
          class PaginationSession
            include PaginationOrchestratorLoadingStateSupport

            attr_reader :doc,
                        :page_calculator,
                        :dimensions,
                        :config_snapshot,
                        :reader_session_snapshot,
                        :reader_session_store,
                        :reader_view_state_store,
                        :reader_pagination_store,
                        :display_capabilities,
                        :instrumentation

            def initialize(doc:, page_calculator:, dimensions:, pagination_cache:,
                           config_snapshot:, reader_session_snapshot:, reader_session_store:,
                           reader_view_state_store:, reader_pagination_store:,
                           display_capabilities:, instrumentation:, logger: nil)
              @doc = doc
              @page_calculator = page_calculator
              @dimensions = dimensions
              @pagination_cache = pagination_cache
              @config_snapshot = config_snapshot
              @reader_session_snapshot = reader_session_snapshot
              @reader_session_store = reader_session_store
              @reader_view_state_store = reader_view_state_store
              @reader_pagination_store = reader_pagination_store
              @display_capabilities = display_capabilities
              @instrumentation = instrumentation
              @logger = logger
            end

            def build_full_map!(progress: nil, &block)
              progress ||= block
              strategy.build_full_map(progress: progress)
            end

            def build_full_map(progress: nil, &)
              build_full_map!(progress: progress, &)
            end

            def update_reader(**attrs)
              persist_session(**attrs)
            end

            def refresh_after_resize
              strategy.refresh_after_resize
            end

            def rebuild_after_config_change
              strategy.rebuild_after_config_change
            end

            # Performs the initial pagination calculation with a loading overlay.
            # Returns a hash with optional :page_map_cache for absolute mode.
            def initial_build
              cache = nil
              with_loading('Calculating pages...') do
                map = strategy.build_initial_map(progress: progress_callback)
                cache = map ? build_absolute_cache_entry(map) : nil
              end
              { page_map_cache: cache }
            end

            # Rebuilds dynamic pagination with a loading overlay and precise restore.
            def rebuild_dynamic
              strategy.rebuild_dynamic(progress: progress_callback)
            end

            # Remove the cached pagination entry for the supplied dimensions.
            #
            # @return [Symbol] :deleted when cache entry removed, :missing when no entry existed,
            #   :error when removal fails.
            def invalidate_cache
              return :missing unless doc && @pagination_cache

              key = @pagination_cache.layout_key(
                width,
                height,
                view_mode,
                line_spacing,
                kitty_images: kitty_images?,
                layout_variant: layout_variant
              )
              return :missing unless key && @pagination_cache.exists_for_document?(doc, key)

              @pagination_cache.delete_for_document(doc, key)
              :deleted
            rescue Shoko::Error => e
              @logger&.debug("pagination_session.invalidate_cache failed: #{e.message}")
              :error
            end

            def width
              dimensions[0]
            end

            def height
              dimensions[1]
            end

            def view_mode
              config_snapshot.view_mode
            end

            def line_spacing
              config_snapshot.line_spacing
            end

            def kitty_images?
              display_capabilities.kitty_images_enabled?(config_snapshot)
            end

            def pending_progress_payload
              current_chapter = reader_session_snapshot.current_chapter
              current_index = reader_session_snapshot.current_page_index.to_i
              page = page_calculator.get_page(
                current_index,
                width: width,
                height: height,
                sidebar_visible: layout_variant == :sidebar
              )
              {
                chapter_index: current_chapter,
                line_offset: page ? page[:start_line] : 0,
              }
            end

            def build_dynamic_map(progress: nil)
              payload = instrumentation.measure('pagination.build') do
                page_calculator.build_dynamic_map!(width,
                                                   height,
                                                   doc,
                                                   config_reader: config_snapshot,
                                                   sidebar_visible: layout_variant == :sidebar) do |done, total|
                  progress&.call(done, total)
                end
              end
              apply_pagination_payload(payload)
              apply_pending_restore_payload(page_calculator.apply_pending_precise_restore!(reader_session_snapshot))
            end

            def sync_sidebar_layout(sidebar_visible:)
              return :pass unless config_snapshot.page_numbering_mode == :dynamic

              result = page_calculator.switch_dynamic_layout_variant!(
                width,
                height,
                doc,
                sidebar_visible: sidebar_visible,
                reader_state_reader: reader_session_snapshot
              )
              return :error unless result.is_a?(Hash)

              status = result[:status] || :error
              return status unless status == :switched

              apply_pagination_payload(result)
              index = result[:current_page_index]
              persist_session(current_page_index: index) if result.key?(:current_page_index) && !index.nil?
              :switched
            end

            def build_absolute_map(progress: nil)
              payload = instrumentation.measure('pagination.build') do
                page_calculator.build_absolute_map!(width,
                                                    height,
                                                    doc,
                                                    config_reader: config_snapshot) do |done, total|
                  progress&.call(done, total)
                end
              end
              apply_pagination_payload(payload)
              payload && payload[:page_map]
            end

            def clamp_dynamic_index!
              total = page_calculator.total_pages.to_i
              return if total <= 0

              current = reader_session_snapshot.current_page_index.to_i
              clamped = current.clamp(0, total - 1)
              persist_session(current_page_index: clamped)
            end

            def build_absolute_cache_entry(page_map)
              key = @pagination_cache&.layout_key(
                width,
                height,
                view_mode,
                line_spacing,
                kitty_images: kitty_images?,
                layout_variant: layout_variant
              )
              {
                key: key,
                map: page_map,
                total: Array(page_map).sum,
              }
            end

            def apply_pagination_payload(payload)
              return unless payload.is_a?(Hash)

              attrs = {}
              attrs[:page_map] = payload[:page_map] if payload.key?(:page_map)
              attrs[:total_pages] = payload[:total_pages] if payload.key?(:total_pages)
              attrs[:last_width] = payload[:last_width] if payload.key?(:last_width)
              attrs[:last_height] = payload[:last_height] if payload.key?(:last_height)
              persist_pagination(**attrs) unless attrs.empty?
            end

            def apply_pending_restore_payload(payload)
              return unless payload.is_a?(Hash)

              index = payload[:current_page_index]
              persist_session(current_page_index: index) if payload.key?(:current_page_index) && !index.nil?
              persist_session(pending_progress: nil) if payload[:clear_pending_progress]
            end

            private

            def strategy
              @strategy ||= StrategyFactory.select(self).new(self)
            end

            def layout_variant
              return :base unless config_snapshot.page_numbering_mode == :dynamic

              reader_view_state_store.sidebar_visible? ? :sidebar : :base
            end

            def persist_session(**attrs)
              snapshot = reader_session_snapshot.with(**attrs)
              @reader_session_snapshot = reader_session_store.save(snapshot)
            end

            def persist_view(**attrs)
              snapshot = reader_view_state_store.load.with(**attrs)
              reader_view_state_store.save(snapshot)
            end

            def persist_pagination(**attrs)
              snapshot = reader_pagination_store.load.with(**attrs)
              reader_pagination_store.save(snapshot)
            end
          end

          # @param reader_runtime_context [Core::Ports::Outbound::ReaderRuntimeContext]
          #   Runtime context for terminal size
          # @param pagination_cache [Object, nil] Pagination cache storage
          # @param instrumentation [Core::Ports::Outbound::Instrumentation] Instrumentation adapter (required)
          def initialize(reader_runtime_context:, instrumentation:, pagination_cache: nil,
                         logger: nil)
            @reader_runtime_context = reader_runtime_context
            @pagination_cache = pagination_cache
            @instrumentation = instrumentation
            @logger = logger
          end

          # Bind document and store dependencies into a reusable runtime handle.
          def bind(doc:, page_calculator:, app_config_store:, reader_session_store:,
                   reader_view_state_store:, reader_pagination_store:)
            return nil unless doc && page_calculator

            PaginationRuntime.new(
              pagination_session_class: PaginationSession,
              doc: doc,
              page_calculator: page_calculator,
              reader_runtime_context: @reader_runtime_context,
              pagination_cache: @pagination_cache,
              instrumentation: @instrumentation,
              app_config_store: app_config_store,
              reader_session_store: reader_session_store,
              reader_view_state_store: reader_view_state_store,
              reader_pagination_store: reader_pagination_store,
              logger: @logger
            )
          end
        end
      end
    end
  end
end
