# frozen_string_literal: true

module Shoko
  module Presentation::Ui::Components
    module Ui
      # Shared helpers for list-based components to keep pagination logic consistent.
      module ListHelpers
        module_function

        def visible_window(total_items, per_page, selected)
          return [0, 0] if total_items <= 0 || per_page <= 0

          clamped_selected = selected.clamp(0, total_items - 1)
          start_index = if clamped_selected < per_page
                          0
                        else
                          clamped_selected - per_page + 1
                        end
          max_start = [total_items - per_page, 0].max
          start_index = [start_index, max_start].min
          end_index = [start_index + per_page - 1, total_items - 1].min
          [start_index, end_index]
        end

        def slice_visible(items, per_page, selected)
          total = items.length
          start_index, end_index = visible_window(total, per_page, selected)
          [start_index, items[start_index..end_index] || []]
        end
      end
    end
  end
end
