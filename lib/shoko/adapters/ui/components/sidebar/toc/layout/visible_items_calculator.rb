# frozen_string_literal: true

module Shoko
  module Adapters::Ui::Components
    module Sidebar
      # Calculates which entries are visible in viewport.
      class VisibleItemsCalculator
        def initialize(entries, visible_indices, selected_index, viewport, full_entries:,
                       collapsed_set:, filter_active:, wrap_cache:, line_index:, text_metrics:)
          @entries = entries
          @visible_indices = visible_indices
          @selected_index = selected_index
          @viewport = viewport
          @full_entries = full_entries
          @collapsed_set = collapsed_set
          @filter_active = filter_active
          @wrap_cache = wrap_cache
          @line_index = line_index
          @text_metrics = text_metrics
        end

        def calculate
          return [] if @entries.empty? || @viewport.height <= 0
          return [] if @line_index.total_height <= 0

          viewport_start = viewport_start_line
          start_index = @line_index.entry_index_for_line(viewport_start) || 0
          start_offset = viewport_start - @line_index.offset_for(start_index)
          items = []
          remaining = @viewport.height
          screen_y = @viewport.start_y
          idx = start_index
          offset = start_offset

          while idx < @entries.length && remaining.positive?
            entry = @entries[idx]
            full_index = @visible_indices[idx]
            config = ItemConfig.new(
              item_entries: @entries,
              entry: entry,
              index: idx,
              full_index: full_index,
              selected_index: @selected_index,
              max_width: @viewport.max_width,
              full_entries: @full_entries,
              collapsed_set: @collapsed_set,
              filter_active: @filter_active,
              wrap_cache: @wrap_cache,
              text_metrics: @text_metrics
            )
            item = VisibleEntryItem.new(config)
            height = item.height
            visible_height = [height - offset, remaining].min
            items << item.with_screen_position(screen_y, offset, visible_height)
            screen_y += visible_height
            remaining -= visible_height
            offset = 0
            idx += 1
          end

          items
        end

        private

        def viewport_start_line
          total_height = @line_index.total_height
          return 0 if total_height <= @viewport.height || @viewport.height <= 0

          selected_index = @selected_index.to_i.clamp(0, @entries.length - 1)
          selected_offset = @line_index.offset_for(selected_index)
          selected_height = @line_index.height_for(selected_index)
          selected_center = selected_offset + (selected_height / 2.0)

          raw_start = selected_center - (@viewport.height / 2.0)
          raw_start = [raw_start, 0].max
          max_start = [total_height - @viewport.height, 0].max
          [raw_start.round, max_start].min
        end
      end
    end
  end
end
