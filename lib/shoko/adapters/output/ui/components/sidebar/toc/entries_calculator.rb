# frozen_string_literal: true

module Shoko
  module Adapters::Output::Ui::Components
    module Sidebar
      # Collection of entries with selection state.
      class EntriesCollection
        attr_reader :full, :visible, :visible_indices, :selected_full_index

        def initialize(full:, visible:, visible_indices:, selected_full_index:)
          @full = full
          @visible = visible
          @visible_indices = visible_indices
          @selected_full_index = selected_full_index
        end

        def empty?
          visible.empty?
        end

        def count
          full.length
        end
      end

      # Calculates the selected index in visible list.
      class SelectedIndexCalculator
        def initialize(entries)
          @entries = entries
        end

        def calculate
          selected_entry = full_entries[selected_full_index]
          find_visible_index(selected_entry)
        end

        private

        def full_entries
          @entries.full
        end

        def visible_entries
          @entries.visible
        end

        def selected_full_index
          @entries.selected_full_index
        end

        def find_visible_index(selected_entry)
          return 0 unless selected_entry

          visible_entries.index(selected_entry) || 0
        end
      end

      # Calculates entries collection with filtering.
      class EntriesCalculator
        def initialize(context)
          @context = context
        end

        def calculate
          full_entries = DocumentEntriesExtractor.new(@context.document).extract
          filtered = apply_filter(full_entries)
          index_map = build_index_map(full_entries)
          visible = apply_collapse(filtered, full_entries, index_map)
          visible_indices = visible.filter_map { |entry| index_map[entry] }

          EntriesCollection.new(
            full: full_entries,
            visible: visible,
            visible_indices: visible_indices,
            selected_full_index: calculate_selected_index(full_entries)
          )
        end

        private

        def apply_filter(entries)
          return entries unless @context.filter_active?

          EntryFilter.new(entries, @context.filter_text).filter
        end

        def apply_collapse(entries, full_entries, index_map)
          return entries unless @context.collapse_enabled?

          collapsed = @context.collapsed_set
          return entries if collapsed.empty?

          CollapsedEntriesFilter.new(entries, full_entries, index_map, collapsed).filter
        end

        def build_index_map(entries)
          hash = {}.compare_by_identity
          entries.each_with_index { |entry, idx| hash[entry] = idx }
          hash
        end

        def calculate_selected_index(entries)
          raw_index = @context.sidebar_state_reader&.sidebar_toc_selected || 0
          max_index = [entries.length - 1, 0].max
          raw_index.to_i.clamp(0, max_index)
        end
      end
    end
  end
end
