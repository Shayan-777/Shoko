# frozen_string_literal: true

require 'set'

module Shoko
  module Adapters::Output::Ui::Components
    module Sidebar
      # Encapsulates TOC rendering context and state.
      class RenderContext
        include Adapters::Output::Ui::Constants::UI

        attr_reader :surface, :bounds, :state, :document, :wrap_cache, :sidebar_state_reader, :text_metrics

        def initialize(surface, bounds, state, document, wrap_cache: nil, entries_cache: nil,
                       sidebar_state_reader: nil, text_metrics:)
          @surface = surface
          @bounds = bounds
          @state = state
          @document = document
          @wrap_cache = wrap_cache || {}
          @entries_cache = entries_cache
          @sidebar_state_reader = sidebar_state_reader
          @text_metrics = text_metrics
        end

        def entries
          return @entries if @entries
          return cached_entries if @entries_cache

          @entries = EntriesCalculator.new(self).calculate
        end

        def selected_index
          @selected_index ||= SelectedIndexCalculator.new(entries).calculate
        end

        def filter_active?
          sidebar_state_reader&.sidebar_toc_filter_active?
        end

        def filter_text
          sidebar_state_reader&.sidebar_toc_filter || ''
        end

        def collapsed_indices
          raw = sidebar_state_reader&.sidebar_toc_collapsed
          Array(raw).map(&:to_i)
        end

        def collapsed_set
          @collapsed_set ||= Set.new(collapsed_indices)
        end

        def collapse_enabled?
          !filter_active?
        end

        def metrics
          @metrics ||= calculate_metrics
        end

        def write(row, col, text)
          surface.write(bounds, row, col, text)
        end

        def scroll_metrics
          @scroll_metrics ||= EntriesScrollMetrics.new(self)
        end

        def entries_layout
          @entries_layout ||= EntriesListLayout.new(self)
        end

        private

        def cached_entries
          @entries = EntriesCollection.new(
            full: @entries_cache.full,
            visible: @entries_cache.visible,
            visible_indices: @entries_cache.visible_indices,
            selected_full_index: selected_full_index_for(@entries_cache.full)
          )
        end

        def selected_full_index_for(entries)
          raw_index = sidebar_state_reader&.sidebar_toc_selected || 0
          max_index = [entries.length - 1, 0].max
          raw_index.to_i.clamp(0, max_index)
        end

        def calculate_metrics
          Metrics.new(
            x: 1,
            y: 1,
            width: bounds.width,
            height: bounds.height
          )
        end
      end
    end
  end
end
