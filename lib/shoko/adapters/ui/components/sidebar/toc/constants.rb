# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Sidebar
          SCROLLBAR_WIDTH = 1
          RIGHT_MARGIN = 2

          EntriesCache = Struct.new(:full, :visible, :visible_indices)
          Metrics = Struct.new(:x, :y, :width, :height)
          ViewportConfig = Struct.new(:start_y, :height, :max_width)
          ItemConfig = Struct.new(
            :item_entries, :entry, :index, :full_index, :selected_index, :max_width,
            :full_entries, :collapsed_set, :filter_active, :wrap_cache, :text_metrics
          )
        end
      end
    end
  end
end
