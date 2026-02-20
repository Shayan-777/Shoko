# frozen_string_literal: true

require_relative '../../../../../core/services/toc_tree_service'

module Shoko
  module Adapters::Ui::Components
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
          @tree_service = Shoko::Core::Services::TocTreeService.instance
        end

        def calculate
          full_entries = @tree_service.entries_for(@context.document)
          visible_indices = @tree_service.visible_indices(
            full_entries,
            collapsed: @context.collapsed_indices,
            filter_text: @context.filter_text,
            filter_active: @context.filter_active?
          )
          visible = visible_indices.map { |idx| full_entries[idx] }.compact

          EntriesCollection.new(
            full: full_entries,
            visible: visible,
            visible_indices: visible_indices,
            selected_full_index: calculate_selected_index(full_entries)
          )
        end

        private

        def calculate_selected_index(entries)
          raw_index = @context.sidebar_state_reader&.sidebar_toc_selected || 0
          max_index = [entries.length - 1, 0].max
          raw_index.to_i.clamp(0, max_index)
        end
      end
    end
  end
end
