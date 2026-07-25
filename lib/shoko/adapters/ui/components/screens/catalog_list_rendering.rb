# frozen_string_literal: true

require_relative '../ui/list_windowing'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # The action-rows-then-scrollable-catalog layout shared by the
          # settings screens that install things: dictionaries and translator
          # packs. Both draw a fixed block of action rows, then a windowed list
          # of catalog entries beneath it, then an empty-state line when the
          # catalog has nothing to show.
          #
          # A genuine multi-host mixin (R1's ≥2-host exemption): the hosts
          # supply the content — `action_items`, `render_action_row`,
          # `selected_index`, `empty_state_message`, `empty_state_fg` — and this
          # supplies the shared layout arithmetic. It previously existed as
          # three method pairs copied between the two screens, two of them
          # under different names.
          module CatalogListRendering
            private

            # Draws the action rows from the top of the frame, stopping at the
            # frame bottom. Returns the row where the catalog may begin (one
            # blank row below the last action).
            def render_actions(list, frame)
              row = frame.body_top
              action_items.each_with_index do |item, index|
                break if row > frame.body_bottom

                render_action_row(list, frame, item: item, index: index, row: row)
                row += 1
              end
              row + 1
            end

            def render_catalog_empty(frame, top, height)
              frame.write_line(top + [height / 2, 0].max, [[empty_state_message, empty_state_fg]])
            end

            # The visible slice of the catalog. Selection is offset by the
            # action rows, which occupy the leading indices of the same cursor.
            def catalog_window(items, height)
              selection = [selected_index - action_items.length, 0].max
              start_index, visible = Ui::ListWindowing.slice_visible(items, height, selection)
              { start: start_index, items: visible }
            end
          end
        end
      end
    end
  end
end
