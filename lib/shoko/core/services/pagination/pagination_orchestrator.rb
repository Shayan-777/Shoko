# frozen_string_literal: true

require_relative '../pagination'
require_relative '../../../adapters/output/kitty/kitty_graphics'
require_relative '../../ports/config_reader'
require_relative '../../ports/state_writer'

module Shoko
  module Core
    module Services
      module Pagination
        # Handles pagination builds (dynamic/absolute) and progress overlay.
        # Keeps heavy orchestration out of ReaderController while preserving behavior.
        #
        # This class follows hexagonal architecture principles:
        # - Config reading goes through ConfigReader port
        # - State writing goes through StateWriter port
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
          class PaginationSession
            attr_reader :doc, :state, :page_calculator, :dimensions, :config_reader, :state_writer

            def initialize(doc:, state:, page_calculator:, dimensions:, pagination_cache:,
                           frame_coordinator:, config_reader:, state_writer:)
              @doc = doc
              @state = state
              @page_calculator = page_calculator
              @dimensions = dimensions
              @pagination_cache = pagination_cache
              @frame_coordinator = frame_coordinator
              @config_reader = config_reader
              @state_writer = state_writer
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

              key = @pagination_cache.layout_key(width, height, view_mode, line_spacing, kitty_images: kitty_images?)
              return :missing unless key && @pagination_cache.exists_for_document?(doc, key)

              @pagination_cache.delete_for_document(doc, key)
              :deleted
            rescue StandardError
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
              Shoko::Adapters::Output::Kitty::KittyGraphics.enabled_for?(state)
            end

            def pending_progress_payload
              current_chapter = state.get(%i[reader current_chapter]) || 0
              current_index = state.get(%i[reader current_page_index]).to_i
              page = page_calculator.get_page(current_index)
              {
                chapter_index: current_chapter,
                line_offset: page ? page[:start_line] : 0,
              }
            end

            def build_dynamic_map(progress: nil)
              Shoko::Adapters::Monitoring::PerfTracer.measure('pagination.build') do
                page_calculator.build_dynamic_map!(width, height, doc,
                                                   state_writer: state_writer,
                                                   config_reader: config_reader) do |done, total|
                  progress&.call(done, total)
                end
              end
              page_calculator.apply_pending_precise_restore!(state, state_writer: state_writer)
            end

            def build_absolute_map(progress: nil)
              Shoko::Adapters::Monitoring::PerfTracer.measure('pagination.build') do
                page_calculator.build_absolute_map!(width, height, doc,
                                                    state_writer: state_writer,
                                                    config_reader: config_reader) do |done, total|
                  progress&.call(done, total)
                end
              end
            end

            def clamp_dynamic_index!
              total = page_calculator.total_pages.to_i
              return if total <= 0

              current = state.get(%i[reader current_page_index]).to_i
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
              @frame_coordinator&.render_loading_overlay
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
              @frame_coordinator&.render_loading_overlay
            end

            def build_absolute_cache_entry(page_map)
              key = @pagination_cache&.layout_key(
                width,
                height,
                view_mode,
                line_spacing,
                kitty_images: kitty_images?
              )
              {
                key: key,
                map: page_map,
                total: Array(page_map).sum,
              }
            end

            private

            def strategy
              @strategy ||= StrategyFactory.select(self).new(self)
            end
          end

          def initialize(terminal_service:, pagination_cache: nil, frame_coordinator: nil)
            @terminal_service = terminal_service
            @pagination_cache = pagination_cache
            @frame_coordinator = frame_coordinator
          end

          # Create a pagination session with the required ports
          # @param config_reader [Core::Ports::ConfigReader] Port for reading config
          # @param state_writer [Core::Ports::StateWriter] Port for writing state
          def session(doc:, state:, page_calculator:, config_reader:, state_writer:, dimensions: nil)
            return nil unless doc && page_calculator

            dims = dimensions || terminal_dimensions
            PaginationSession.new(
              doc: doc,
              state: state,
              page_calculator: page_calculator,
              dimensions: dims,
              pagination_cache: @pagination_cache,
              frame_coordinator: @frame_coordinator,
              config_reader: config_reader,
              state_writer: state_writer
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
