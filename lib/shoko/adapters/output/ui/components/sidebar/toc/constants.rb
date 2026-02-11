# frozen_string_literal: true

module Shoko
  module Adapters::Output::Ui::Components
    module Sidebar
      SCROLLBAR_WIDTH = 1
      RIGHT_MARGIN = 2

      EntriesCache = Struct.new(:full, :visible, :visible_indices, keyword_init: true)
      Metrics = Struct.new(:x, :y, :width, :height, keyword_init: true)
      ViewportConfig = Struct.new(:start_y, :height, :max_width, keyword_init: true)
      ItemConfig = Struct.new(
        :item_entries, :entry, :index, :full_index, :selected_index, :max_width,
        :full_entries, :collapsed_set, :filter_active, :wrap_cache, :text_metrics,
        keyword_init: true
      )
    end
  end
end
