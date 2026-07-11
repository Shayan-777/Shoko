# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          # Shared helpers for list-based components to keep pagination logic consistent.
          module ListWindowing
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

            # Thumb geometry for a right-edge scrollbar: a track of +track_rows+
            # rows over +total+ items with +visible+ of them on screen, scrolled
            # to +scroll+. Returns { size:, start: } in track rows.
            def scrollbar_thumb(total:, visible:, scroll:, track_rows: visible)
              items = [total, 1].max
              size = (visible.to_f / items * track_rows).round.clamp(1, track_rows)
              room = track_rows - size
              denom = [items - visible, 1].max
              start = room <= 0 ? 0 : ((scroll.to_f / denom) * room).round.clamp(0, room)
              { size: size, start: start }
            end

            # Scroll offset that keeps +index+ inside a +visible+-row window over
            # +total+ items, moving the current +scroll+ as little as possible and
            # clamping to the list bounds.
            def scroll_to_reveal(index, scroll:, visible:, total:)
              window = [visible, 1].max
              offset = scroll
              offset = index if index < offset
              offset = index - window + 1 if index >= offset + window
              offset.clamp(0, [total - window, 0].max)
            end
          end
        end
      end
    end
  end
end
