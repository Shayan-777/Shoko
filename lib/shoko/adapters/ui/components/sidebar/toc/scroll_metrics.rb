# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Sidebar
          # Computes scroll metrics for TOC entries within the content viewport.
          class EntriesScrollMetrics
            attr_reader :track_start_y, :track_height, :thumb_start_y, :thumb_height, :total_items,
                        :total_height, :viewport_height, :viewport_start, :max_start,
                        :scrollbar_start_col, :scrollbar_end_col, :visible_indices,
                        :selected_full_index, :selected_visible_index, :navigable_indices

            def initialize(context)
              @context = context
              @layout = context.entries_layout
              @visible_entries = context.entries.visible
              @visible_indices = context.entries.visible_indices
              assign_layout_metrics(context)
              assign_selection_metrics(context)
              assign_thumb_metrics
              @navigable_indices = build_navigable_indices
              @nav_positions = build_nav_positions
            end

            def scrollable?
              @track_height.positive? && @total_height.positive?
            end

            def absolute_scrollbar_start_col
              @context.bounds.x + @scrollbar_start_col - 1
            end

            def absolute_scrollbar_end_col
              @context.bounds.x + @scrollbar_end_col - 1
            end

            def absolute_track_start_y
              @context.bounds.y + @track_start_y - 1
            end

            def absolute_track_end_y
              absolute_track_start_y + @track_height - 1
            end

            def absolute_thumb_start_y
              @context.bounds.y + @thumb_start_y - 1
            end

            def hit_scrollbar?(abs_col, abs_row)
              return false unless scrollable?

              abs_col.between?(absolute_scrollbar_start_col, absolute_scrollbar_end_col) &&
                abs_row.between?(absolute_track_start_y, absolute_track_end_y)
            end

            def row_in_track?(abs_row)
              return false unless scrollable?

              abs_row.between?(absolute_track_start_y, absolute_track_end_y)
            end

            def hit_thumb?(abs_col, abs_row)
              return false unless hit_scrollbar?(abs_col, abs_row)
              return false unless @thumb_height.positive?

              abs_row.between?(absolute_thumb_start_y, absolute_thumb_start_y + @thumb_height - 1)
            end

            def full_index_for_abs_row(abs_row)
              full_index_for_row(abs_row - @context.bounds.y + 1)
            end

            def full_index_for_row(local_row)
              return nil unless scrollable?
              return nil if @visible_indices.empty?
              return @visible_indices.first if @max_start <= 0 || @track_height <= 1

              clamped = [local_row - @track_start_y, 0].max
              clamped = [clamped, @track_height - 1].min
              ratio = clamped.to_f / (@track_height - 1)
              viewport_start = (ratio * @max_start).round
              target_line = viewport_start + (@viewport_height / 2.0)
              target_index = @layout.line_index.entry_index_for_line(target_line) || 0
              @visible_indices[target_index]
            end

            def nav_position_for(full_index)
              @nav_positions[full_index]
            end

            private

            def assign_layout_metrics(context)
              @total_items = @visible_entries.length
              @total_height = @layout.total_height
              @viewport_height = @layout.available_height
              @scrollbar_end_col = context.metrics.width
              @scrollbar_start_col = [@scrollbar_end_col - SCROLLBAR_WIDTH + 1, 1].max
              @track_start_y = @layout.content_start_y
              @track_height = @layout.available_height
              @max_start = [@total_height - @viewport_height, 0].max
            end

            def assign_selection_metrics(context)
              @selected_visible_index = context.selected_index
              @selected_full_index = context.entries.selected_full_index
            end

            def assign_thumb_metrics
              @viewport_start = calculate_viewport_start
              @thumb_height = calculate_thumb_height
              @thumb_start_y = calculate_thumb_start
            end

            def calculate_viewport_start
              return 0 if @total_height <= @viewport_height || @viewport_height <= 0

              selected_index = @selected_visible_index.to_i.clamp(0, @visible_entries.length - 1)
              selected_offset = @layout.line_index.offset_for(selected_index)
              selected_height = @layout.line_index.height_for(selected_index)
              selected_center = selected_offset + (selected_height / 2.0)

              raw = selected_center - (@viewport_height / 2.0)
              raw = [raw, 0].max
              [raw.round, @max_start].min
            end

            def calculate_thumb_height
              return 0 unless scrollable?
              return @track_height if @max_start <= 0

              height = (@viewport_height.to_f / @total_height) * @track_height
              [height.round, 1].max
            end

            def calculate_thumb_start
              return @track_start_y unless scrollable?
              return @track_start_y if @max_start <= 0 || @track_height <= @thumb_height

              offset = ((@viewport_start.to_f / @max_start) * (@track_height - @thumb_height)).round
              @track_start_y + offset
            end

            def build_navigable_indices
              navigable = []
              @visible_entries.each_with_index do |entry, idx|
                navigable << @visible_indices[idx] if entry&.chapter_index
              end
              navigable.empty? ? @visible_indices.dup : navigable
            end

            def build_nav_positions
              positions = {}
              @navigable_indices.each_with_index { |idx, pos| positions[idx] = pos }
              positions
            end
          end
        end
      end
    end
  end
end
