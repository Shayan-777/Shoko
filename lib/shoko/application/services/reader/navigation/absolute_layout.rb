# frozen_string_literal: true

require_relative 'snapshot_queries'
require 'shoko/core/models/reader_settings'

module Shoko
  module Application
    module Services
      module Reader
        module Navigation
          # Computes absolute-layout metrics and enriches navigation contexts.
          # Uses session stores/runtime context - no state-slice ports.
          class AbsoluteLayout
            # Snapshot of layout-derived values for absolute navigation.
            LayoutState = Struct.new(:snapshot, :view_mode, :metrics, :stride)

            def initialize(layout_service:, app_config_store:, reader_session_store:, reader_state_reader:,
                           reader_runtime_context:,
                           logger: nil)
              @layout_service = layout_service
              @app_config_store = app_config_store
              @reader_session_store = reader_session_store
              @reader_state_reader = reader_state_reader
              @reader_runtime_context = reader_runtime_context
              @logger = logger
            end

            def build
              snapshot = build_snapshot
              view_mode = extract_view_mode(snapshot)
              metrics = { single: lines_for(snapshot, :single), split: lines_for(snapshot, :split) }
              stride = view_mode == :split ? metrics[:split] : metrics[:single]
              stride = metrics[:single] if stride.to_i <= 0
              stride = 1 if stride.to_i <= 0
              LayoutState.new(snapshot: snapshot, view_mode: view_mode, metrics: metrics, stride: stride)
            end

            def populate_context(ctx)
              return ctx unless ctx.mode == :absolute

              layout_state = build
              ctx.lines_per_page = layout_state.metrics[:single]
              ctx.column_lines_per_page = layout_state.metrics[:split]
              ctx.max_page_in_chapter = page_count(layout_state.snapshot, ctx.current_chapter)
              ctx.max_offset_in_chapter = max_offset_for(layout_state.snapshot,
                                                         ctx.current_chapter,
                                                         layout_state.stride)
              ctx
            end

            def page_count(snapshot, chapter_index)
              return 0 if chapter_index.nil?

              page_map = snapshot[:page_map] || []
              page_map[chapter_index] || 0
            end

            def max_offset_for(snapshot, chapter_index, stride)
              return 0 if chapter_index.nil? || stride.to_i <= 0

              pages = page_count(snapshot, chapter_index).to_i
              return 0 if pages <= 1

              (pages - 1) * stride
            end

            def column_width(snapshot, view_mode)
              return fallback_width(snapshot) unless @layout_service

              width = fallback_width(snapshot)
              height = fallback_height(snapshot)
              col_width, = @layout_service.calculate_metrics(width, height, view_mode)
              col_width = width if col_width.to_i <= 0
              col_width
            rescue Shoko::Error => e
              @logger&.debug("absolute_layout.column_width failed: #{e.message}")
              fallback_width(snapshot)
            end

            private

            def build_snapshot
              SnapshotQueries.build_snapshot(
                config_snapshot: @app_config_store.load,
                reader_session_snapshot: @reader_session_store.load,
                reader_pagination_snapshot: @reader_state_reader.load,
                terminal_size: @reader_runtime_context.terminal_size
              )
            end

            def extract_view_mode(snapshot)
              snapshot[:view_mode] || :single
            end

            def lines_for(snapshot, view_mode)
              return fallback_lines(view_mode) unless @layout_service

              width = fallback_width(snapshot)
              height = fallback_height(snapshot)
              _, content_height = @layout_service.calculate_metrics(width, height, view_mode)
              line_spacing = snapshot[:line_spacing] || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
              lines = @layout_service.adjust_for_line_spacing(content_height, line_spacing)
              lines = 1 if lines.to_i <= 0
              lines
            rescue Shoko::Error => e
              @logger&.debug("absolute_layout.lines_for failed: #{e.message}")
              1
            end

            def fallback_width(snapshot)
              snapshot[:terminal_width] || @reader_runtime_context.terminal_size.width
            end

            def fallback_height(snapshot)
              snapshot[:terminal_height] || @reader_runtime_context.terminal_size.height
            end

            def fallback_lines(view_mode)
              view_mode == :split ? 2 : 1
            end
          end
        end
      end
    end
  end
end
