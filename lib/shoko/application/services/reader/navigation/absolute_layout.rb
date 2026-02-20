# frozen_string_literal: true

require_relative 'context_helpers'

module Shoko
  module Application
    module Services
      module Reader
        module Navigation
        # Computes absolute-layout metrics and enriches navigation contexts.
        # Uses hexagonal ports for reading state - no direct state_store access.
        class AbsoluteLayout
          # Snapshot of layout-derived values for absolute navigation.
          LayoutState = Struct.new(:snapshot, :view_mode, :metrics, :stride, keyword_init: true)

          # @param layout_service [Object] Layout calculation service
          # @param config_reader [Application::Ports::ConfigReader] Port for reading config
          # @param reader_state_reader [Application::Ports::ReaderNavigationReader] Port for reading reader state
          # @param ui_state_reader [Application::Ports::UiStateReader] Port for reading UI state
          def initialize(layout_service:, config_reader:, reader_state_reader:, ui_state_reader:, logger: nil)
            @layout_service = layout_service
            @config_reader = config_reader
            @reader_state_reader = reader_state_reader
            @ui_state_reader = ui_state_reader
            @logger = logger
          end

          def build
            snapshot = build_snapshot
            view_mode = extract_view_mode(snapshot)
            metrics = {
              single: lines_for(snapshot, :single),
              split: lines_for(snapshot, :split),
            }
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
            ctx.max_offset_in_chapter = max_offset_for(layout_state.snapshot, ctx.current_chapter, layout_state.stride)
            ctx
          end

          def page_count(snapshot, chapter_index)
            return 0 if chapter_index.nil?

            page_map = snapshot.dig(:reader, :page_map) || @reader_state_reader&.page_map || []
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
          rescue StandardError => e
            @logger&.debug("absolute_layout.column_width failed: #{e.message}")
            fallback_width(snapshot)
          end

          private

          def build_snapshot
            snapshot = ContextHelpers.build_snapshot_from_ports(
              config_reader: @config_reader,
              reader_state_reader: @reader_state_reader
            )
            # Add UI state
            snapshot[:ui] = {
              terminal_width: @ui_state_reader.terminal_width,
              terminal_height: @ui_state_reader.terminal_height,
            }
            # Add line_spacing to config
            snapshot[:config][:line_spacing] = @config_reader.line_spacing
            snapshot
          end

          def extract_view_mode(snapshot)
            snapshot.dig(:config, :view_mode) || :single
          end

          def lines_for(snapshot, view_mode)
            return fallback_lines(view_mode) unless @layout_service

            width = fallback_width(snapshot)
            height = fallback_height(snapshot)
            _, content_height = @layout_service.calculate_metrics(width, height, view_mode)
            line_spacing = snapshot.dig(:config, :line_spacing) || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
            lines = @layout_service.adjust_for_line_spacing(content_height, line_spacing)
            lines = 1 if lines.to_i <= 0
            lines
          rescue StandardError => e
            @logger&.debug("absolute_layout.lines_for failed: #{e.message}")
            1
          end

          def fallback_width(snapshot)
            snapshot.dig(:ui, :terminal_width) || @ui_state_reader.terminal_width
          end

          def fallback_height(snapshot)
            snapshot.dig(:ui, :terminal_height) || @ui_state_reader.terminal_height
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
