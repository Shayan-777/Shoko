# frozen_string_literal: true

require_relative '../../../core/ports/outbound/config_reader'
require_relative '../../../core/ports/outbound/reader_navigation_reader'
require_relative '../../../core/ports/outbound/pagination_state_writer'
require_relative '../../../core/ports/outbound/ui_loading_writer'

module Shoko
  module Application
    module Services
      module Pagination
        # Handles pagination builds (dynamic/absolute) and progress overlay.
        # Keeps heavy orchestration out of ReaderController while preserving behavior.
        #
        # This class follows hexagonal architecture principles:
        # - Config reading goes through ConfigReader port
        # - State writing goes through PaginationStateWriter port
        class PaginationOrchestrator
          # Factory for selecting per-mode pagination strategies.
          module StrategyFactory
            module_function

            def select(session)
              mode = session.config_reader.page_numbering_mode
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
              session.state_writer.update_selections(pending_progress: payload)
              session.build_dynamic_map
              session.clamp_dynamic_index!
            end

            def rebuild_dynamic(progress:)
              payload = session.pending_progress_payload
              session.with_loading('Rebuilding pagination…') do
                session.state_writer.update_selections(pending_progress: payload)
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
          # Uses hexagonal ports for reading state - no direct state_store access.
          class PaginationSession
            attr_reader :doc, :page_calculator, :dimensions, :config_reader, :reader_state_reader,
                        :state_writer, :display_capabilities, :instrumentation

            def initialize(doc:, page_calculator:, dimensions:, pagination_cache:,
                           config_reader:, reader_state_reader:, state_writer:,
                           display_capabilities:, instrumentation:, logger: nil)
              @doc = doc
              @page_calculator = page_calculator
              @dimensions = dimensions
              @pagination_cache = pagination_cache
              @config_reader = config_reader
              @reader_state_reader = reader_state_reader
              @state_writer = state_writer
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
            rescue StandardError => e
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
              config_reader.view_mode
            end

            def line_spacing
              config_reader.line_spacing
            end

            def kitty_images?
              display_capabilities.kitty_images_enabled?(config_reader)
            end

            def pending_progress_payload
              current_chapter = reader_state_reader.current_chapter
              current_index = reader_state_reader.current_page_index.to_i
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
                page_calculator.build_dynamic_map!(width, height, doc,
                                                   config_reader: config_reader,
                                                   sidebar_visible: layout_variant == :sidebar) do |done, total|
                  progress&.call(done, total)
                end
              end
              apply_pagination_payload(payload)
              apply_pending_restore_payload(page_calculator.apply_pending_precise_restore!(reader_state_reader))
            end

            def sync_sidebar_layout(sidebar_visible:)
              return :pass unless config_reader.page_numbering_mode == :dynamic
              return :pass unless page_calculator.respond_to?(:switch_dynamic_layout_variant!)

              result = page_calculator.switch_dynamic_layout_variant!(
                width,
                height,
                doc,
                sidebar_visible: sidebar_visible,
                reader_state_reader: reader_state_reader
              )
              return :error unless result.is_a?(Hash)

              status = result[:status] || :error
              return status unless status == :switched

              apply_pagination_payload(result)
              index = result[:current_page_index]
              state_writer.update_page(current_page_index: index) if index
              :switched
            end

            def build_absolute_map(progress: nil)
              payload = instrumentation.measure('pagination.build') do
                page_calculator.build_absolute_map!(width, height, doc,
                                                    config_reader: config_reader) do |done, total|
                  progress&.call(done, total)
                end
              end
              apply_pagination_payload(payload)
              payload && payload[:page_map]
            end

            def clamp_dynamic_index!
              total = page_calculator.total_pages.to_i
              return if total <= 0

              current = reader_state_reader.current_page_index.to_i
              clamped = current.clamp(0, total - 1)
              state_writer.update_page(current_page_index: clamped)
            end

            def progress_callback
              ->(done, total) { update_progress(done, total) }
            end

            def with_loading(message)
              begin_loading(message)
              yield
            ensure
              end_loading
            end

            def begin_loading(message)
              state_writer.update_ui_loading(
                loading_active: true,
                loading_message: message,
                loading_progress: 0.0
              )
            end

            def end_loading
              state_writer.update_ui_loading(
                loading_active: false,
                loading_message: nil
              )
            end

            def update_progress(done, total)
              progress = Shoko::Core::Services::ProgressHelper.ratio(done, total)
              state_writer.update_ui_loading(loading_progress: progress)
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
              state_writer.update_pagination_state(attrs) unless attrs.empty?
            end

            def apply_pending_restore_payload(payload)
              return unless payload.is_a?(Hash)

              index = payload[:current_page_index]
              state_writer.update_page(current_page_index: index) if index
              state_writer.update_selections(pending_progress: nil) if payload[:clear_pending_progress]
            end

            private

            def strategy
              @strategy ||= StrategyFactory.select(self).new(self)
            end

            def layout_variant
              return :base unless config_reader.page_numbering_mode == :dynamic

              reader_state_reader&.sidebar_visible? ? :sidebar : :base
            rescue StandardError
              :base
            end
          end

          # @param terminal_service [Object] Terminal service for dimensions
          # @param pagination_cache [Object, nil] Pagination cache storage
          # @param display_capabilities [Core::Ports::Outbound::DisplayCapabilities] Display capability adapter (required)
          # @param instrumentation [Core::Ports::Outbound::Instrumentation] Instrumentation adapter (required)
          def initialize(terminal_service:, display_capabilities:, instrumentation:, pagination_cache: nil,
                         logger: nil)
            @terminal_service = terminal_service
            @pagination_cache = pagination_cache
            @display_capabilities = display_capabilities
            @instrumentation = instrumentation
            @logger = logger
          end

          # Create a pagination session with the required ports
          # @param config_reader [Core::Ports::Outbound::ConfigReader] Port for reading config
          # @param reader_state_reader [Core::Ports::Outbound::ReaderNavigationReader] Port for reading reader state
          # @param state_writer [Core::Ports::Outbound::PaginationStateWriter] Port for writing state
          def session(doc:, page_calculator:, config_reader:, reader_state_reader:, state_writer:, dimensions: nil)
            return nil unless doc && page_calculator

            dims = dimensions || terminal_dimensions
            PaginationSession.new(
              doc: doc,
              page_calculator: page_calculator,
              dimensions: dims,
              pagination_cache: @pagination_cache,
              config_reader: config_reader,
              reader_state_reader: reader_state_reader,
              state_writer: state_writer,
              display_capabilities: @display_capabilities,
              instrumentation: @instrumentation,
              logger: @logger
            )
          end

          private

          def terminal_dimensions
            height, width = @terminal_service.size
            [width, height]
          end
        end
      end
    end
  end
end
