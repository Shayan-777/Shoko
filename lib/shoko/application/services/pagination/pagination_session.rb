# frozen_string_literal: true

require_relative 'strategy_factory'

module Shoko
  module Application
    module Services
      module Pagination
        # Aggregates pagination inputs and exposes a per-document session API.
        class PaginationSession

          attr_reader :doc,
                      :page_calculator,
                      :config_snapshot,
                      :layout_spec,
                      :display_capabilities,
                      :instrumentation

          def initialize(doc:, page_calculator:, config_snapshot:, layout_spec:, pagination_cache:,
                         state_sync:, display_capabilities:, instrumentation:, restore_manager:, logger: nil)
            @doc = doc
            @page_calculator = page_calculator
            @config_snapshot = config_snapshot
            @layout_spec = layout_spec
            @pagination_cache = pagination_cache
            @state_sync = state_sync
            @display_capabilities = display_capabilities
            @instrumentation = instrumentation
            @restore_manager = restore_manager
            @logger = logger
          end

          def reader_session_snapshot
            @state_sync.reader_session_snapshot
          end

          def build_full_map!(progress: nil, &block)
            progress ||= block
            strategy.build_full_map(progress: progress)
          end

          def build_full_map(progress: nil, &)
            build_full_map!(progress: progress, &)
          end

          def update_reader(**attrs)
            @state_sync.persist_session(**attrs)
          end

          def refresh_after_resize
            strategy.refresh_after_resize
          end

          def rebuild_after_config_change
            strategy.rebuild_after_config_change
          end

          def initial_build
            cache = nil
            with_loading('Calculating pages...') do
              map = strategy.build_initial_map(progress: progress_callback)
              cache = map ? build_absolute_cache_entry(map) : nil
            end
            { page_map_cache: cache }
          end

          def rebuild_dynamic
            strategy.rebuild_dynamic(progress: progress_callback)
          end

          def invalidate_cache
            return :missing unless doc && @pagination_cache

            key = layout_spec.cache_key
            return :missing unless key && @pagination_cache.exists_for_document?(doc, key)

            @pagination_cache.delete_for_document(doc, key)
            :deleted
          rescue Shoko::Error => e
            @logger&.debug("pagination_session.invalidate_cache failed: #{e.message}")
            :error
          end

          def width = layout_spec.width
          def height = layout_spec.height
          def view_mode = layout_spec.view_mode
          def line_spacing = layout_spec.line_spacing
          def kitty_images? = layout_spec.kitty_images
          def layout_variant = layout_spec.layout_variant

          def pending_progress_payload
            @restore_manager.pending_progress_payload
          end

          def build_dynamic_map(progress: nil)
            payload = instrumentation.measure('pagination.build') do
              page_calculator.build_dynamic_map!(
                width,
                height,
                doc,
                config_reader: config_snapshot,
                sidebar_visible: layout_variant == :sidebar
              ) do |done, total|
                progress&.call(done, total)
              end
            end
            apply_pagination_payload(payload)
            restore = page_calculator.apply_pending_precise_restore!(reader_session_snapshot)
            @restore_manager.apply_restore_payload(restore)
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
            @state_sync.persist_session(current_page_index: index) if result.key?(:current_page_index) && !index.nil?
            :switched
          end

          def build_absolute_map(progress: nil)
            payload = instrumentation.measure('pagination.build') do
              page_calculator.build_absolute_map!(width, height, doc, config_reader: config_snapshot) do |done, total|
                progress&.call(done, total)
              end
            end
            apply_pagination_payload(payload)
            payload && payload[:page_map]
          end

          def clamp_dynamic_index!
            @restore_manager.clamp_dynamic_index!
          end

          def persist_view(**attrs)
            @state_sync.persist_view(**attrs)
          end


          # Loading-state helpers shared by pagination orchestration sessions.
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
            persist_view(loading_active: true, loading_message: message, loading_progress: 0.0)
          end

          def end_loading
            persist_view(loading_active: false, loading_message: nil)
          end

          def update_progress(done, total)
            progress = Shoko::Core::Services::ProgressHelper.ratio(done, total)
            persist_view(loading_progress: progress)
          end
          private

          def strategy
            @strategy ||= PaginationStrategyFactory.select(self).new(self)
          end

          def build_absolute_cache_entry(page_map)
            {
              key: layout_spec.cache_key,
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
            @state_sync.persist_pagination(**attrs) unless attrs.empty?
          end
        end
      end
    end
  end
end
