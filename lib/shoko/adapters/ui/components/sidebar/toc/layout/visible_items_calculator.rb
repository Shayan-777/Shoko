# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Sidebar
          # Calculates which entries are visible in viewport.
          class VisibleItemsCalculator
            ViewState = Struct.new(:items, :remaining, :screen_y, :idx, :offset)

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
              return [] unless renderable_viewport?

              state = build_view_state
              append_visible_items(state)
              state.items
            end

            private

            def renderable_viewport?
              !@entries.empty? && @viewport.height.positive? && @line_index.total_height.positive?
            end

            def build_view_state
              viewport_start = viewport_start_line
              start_index = @line_index.entry_index_for_line(viewport_start) || 0
              ViewState.new(
                [],
                @viewport.height,
                @viewport.start_y,
                start_index,
                viewport_start - @line_index.offset_for(start_index)
              )
            end

            def append_visible_items(state)
              while state.idx < @entries.length && state.remaining.positive?
                item = visible_item_for(state.idx)
                append_visible_item(state, item)
              end
            end

            def visible_item_for(index)
              full_index = @visible_indices[index]
              config = ItemConfig.new(
                item_entries: @entries,
                entry: @entries[index],
                index: index,
                full_index: full_index,
                selected_index: @selected_index,
                max_width: @viewport.max_width,
                full_entries: @full_entries,
                collapsed_set: @collapsed_set,
                filter_active: @filter_active,
                wrap_cache: @wrap_cache,
                text_metrics: @text_metrics
              )
              VisibleEntryItem.new(config)
            end

            def append_visible_item(state, item)
              visible_height = [item.height - state.offset, state.remaining].min
              state.items << item.with_screen_position(state.screen_y, state.offset, visible_height)
              state.screen_y += visible_height
              state.remaining -= visible_height
              state.offset = 0
              state.idx += 1
            end

            def viewport_start_line
              return 0 unless viewport_scrollable?

              clamp_viewport_start(selected_center_line - (@viewport.height / 2.0))
            end

            def viewport_scrollable?
              @viewport.height.positive? && @line_index.total_height > @viewport.height
            end

            def selected_center_line
              selected_index = @selected_index.to_i.clamp(0, @entries.length - 1)
              selected_offset = @line_index.offset_for(selected_index)
              selected_height = @line_index.height_for(selected_index)
              selected_offset + (selected_height / 2.0)
            end

            def clamp_viewport_start(raw_start)
              max_start = [@line_index.total_height - @viewport.height, 0].max
              raw_start.round.clamp(0, max_start)
            end
          end
        end
      end
    end
  end
end
