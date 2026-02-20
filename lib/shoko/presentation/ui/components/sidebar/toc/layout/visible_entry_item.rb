# frozen_string_literal: true

module Shoko
  module Presentation::Ui::Components
    module Sidebar
      # Represents a single entry item with rendering info.
      class VisibleEntryItem
        attr_reader :entry, :index, :full_index, :max_width

        def initialize(config)
          @config = config
          @entry = config.entry
          @index = config.index
          @full_index = config.full_index
          @max_width = config.max_width
        end

        def with_screen_position(screen_y, start_offset, visible_height)
          PositionedEntryItem.new(self, screen_y, start_offset, visible_height)
        end

        def selected?
          index == @config.selected_index
        end

        def height
          wrapped_lines.length
        end

        def wrapped_lines
          @wrapped_lines ||= EntryLayoutHelper.wrap_lines(@entry, @max_width, @config.wrap_cache, @config.text_metrics)
        end

        def components
          @components ||= EntryComponents.new(
            @config.item_entries,
            @entry,
            @index,
            full_entries: @config.full_entries,
            full_index: @config.full_index,
            collapsed_set: @config.collapsed_set,
            filter_active: @config.filter_active,
            text_metrics: @config.text_metrics
          )
        end
      end

      # Item with screen position.
      class PositionedEntryItem
        attr_reader :screen_y, :start_offset, :visible_height

        def initialize(item, screen_y, start_offset, visible_height)
          @item = item
          @screen_y = screen_y
          @start_offset = start_offset
          @visible_height = visible_height
        end

        def entry
          @item.entry
        end

        def index
          @item.index
        end

        def full_index
          @item.full_index
        end

        def max_width
          @item.max_width
        end

        def selected?
          @item.selected?
        end

        def height
          @visible_height
        end

        def wrapped_lines
          @item.wrapped_lines
        end

        def components
          @item.components
        end
      end
    end
  end
end
