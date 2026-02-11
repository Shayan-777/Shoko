# frozen_string_literal: true

module Shoko
  module Adapters::Output::Ui::Components
    module Sidebar
      # Calculates layout information for TOC entries.
      class EntriesListLayout
        attr_reader :content_start_y, :available_height, :max_width

        def initialize(context)
          @context = context
          @content_start_y = compute_content_start_y
          @available_height = compute_available_height
          @max_width = compute_max_width
        end

        def visible_items
          return [] if @context.entries.empty? || @available_height <= 0

          viewport = create_viewport_config
          VisibleItemsCalculator.new(
            @context.entries.visible,
            @context.entries.visible_indices,
            @context.selected_index,
            viewport,
            full_entries: @context.entries.full,
            collapsed_set: @context.collapsed_set,
            filter_active: @context.filter_active?,
            wrap_cache: @context.wrap_cache,
            line_index: line_index,
            text_metrics: @context.text_metrics
          ).calculate
        end

        def item_at(row)
          visible_items.find do |item|
            row >= item.screen_y && row < (item.screen_y + item.visible_height)
          end
        end

        def total_height
          line_index.total_height
        end

        def line_index
          @line_index ||= LineIndex.new(@context.entries.visible, @max_width, @context.wrap_cache, @context.text_metrics)
        end

        private

        def create_viewport_config
          ViewportConfig.new(
            start_y: @content_start_y,
            height: @available_height,
            max_width: @max_width
          )
        end

        def compute_content_start_y
          base = @context.metrics.y + 2
          base += 2 if @context.filter_active?
          base
        end

        def compute_available_height
          metrics = @context.metrics
          total = metrics.height - (@content_start_y - metrics.y)
          [total, 0].max
        end

        def compute_max_width
          [@context.metrics.width - 2 - SCROLLBAR_WIDTH - RIGHT_MARGIN, 0].max
        end
      end
    end
  end
end
