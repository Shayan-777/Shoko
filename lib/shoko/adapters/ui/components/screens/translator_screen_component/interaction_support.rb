# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Selection and context-menu interaction helpers for the translator screen.
          module TranslatorScreenComponentInteractionSupport
            CONTEXT_MENU_ACTIONS = [
              { id: :copy_to_clipboard, label: 'Copy to Clipboard' },
              { id: :paste_from_clipboard, label: 'Paste from Clipboard' },
            ].freeze

            def body_hit(column, row, bounds)
              layout = layout_metrics(bounds)

              source_hit = body_hit_for_box(layout[:left_box], column, row, :source)
              return source_hit if source_hit

              body_hit_for_box(layout[:right_box], column, row, :target)
            end

            def selection_from_points(start_column:, start_row:, end_column:, end_row:, bounds:)
              start_hit = body_hit(start_column, start_row, bounds)
              end_hit = body_hit(end_column, end_row, bounds)
              return nil unless start_hit && end_hit
              return nil unless start_hit[:kind] == end_hit[:kind]

              start_index, end_index = [start_hit[:index], end_hit[:index]].minmax
              return nil if start_index == end_index

              {
                pane: start_hit[:kind],
                start_index: start_index,
                end_index: end_index,
              }
            end

            def selection_text(selection = translator_selection)
              return '' unless selection

              kind = selection[:pane].to_sym
              start_index, end_index = selection_bounds(selection)
              return '' if end_index <= start_index

              body_text(kind)[start_index...end_index].to_s
            end

            def selection_contains_hit?(selection, hit)
              return false unless selection && hit
              return false unless selection[:pane].to_sym == hit[:kind].to_sym

              start_index, end_index = selection_bounds(selection)
              return false if end_index <= start_index

              if hit[:inside_cluster]
                hit[:cluster_start_index] < end_index && hit[:cluster_end_index] > start_index
              else
                hit[:index] > start_index && hit[:index] < end_index
              end
            end

            def context_menu_hit(column, row, bounds)
              popup_box = context_menu_popup_box(bounds)
              return nil unless popup_box
              return nil unless within_context_menu?(popup_box, column, row)

              action = context_menu_action_at(popup_box, row)
              return nil unless context_menu_action_enabled?(action[:id])

              action
            end

            def context_menu_popup_box(bounds)
              menu = translator_context_menu
              return nil unless menu

              width = context_menu_width
              height = context_menu_actions.length + 2
              col = menu[:anchor_column].to_i.clamp(1, [bounds.width - width + 1, 1].max)
              row = adjusted_context_menu_row(menu[:anchor_row].to_i, height, bounds.height)
              Ui::BoxDrawer::BoxSpec.new(row: row, col: col, width: width, height: height)
            end

            def context_menu_actions
              CONTEXT_MENU_ACTIONS
            end

            private

            def body_hit_for_box(box, column, row, kind)
              return nil unless within_body?(box, column, row, kind)

              width = body_width(box)
              line_index = row - body_start_row(box, kind)
              line = visible_body_line(kind, width, line_index)
              rel_column = (column - (box.col + 2)).clamp(0, width)
              index, cluster = index_for_line_column(line, rel_column)
              {
                kind: kind,
                index: index,
                line_index: line_index,
                cluster_start_index: cluster&.start_index,
                cluster_end_index: cluster&.end_index,
                inside_cluster: !cluster.nil?,
              }
            end

            def visible_body_line(kind, width, line_index)
              layouts = body_layouts(kind, width)
              return layouts[line_index] if layouts[line_index]

              layouts.last || build_line_layout('', 0, 0, [])
            end

            def index_for_line_column(line, column)
              line.clusters.each do |cluster|
                return [cluster.start_index, nil] if column < cluster.column_start
                next unless column < cluster.column_end

                midpoint = cluster.column_start + ((cluster.column_end - cluster.column_start) / 2.0)
                index = column < midpoint ? cluster.start_index : cluster.end_index
                return [index, cluster]
              end

              [line.end_index, nil]
            end

            def context_menu_width
              label_width = context_menu_actions.map do |action|
                Shoko::Shared::Terminal::TextMetrics.visible_length(action[:label])
              end.max || 0
              label_width + 4
            end

            def within_context_menu?(popup_box, column, row)
              column.between?(popup_box.col + 1, popup_box.col + popup_box.width - 2) &&
                row.between?(popup_box.row + 1, popup_box.row + context_menu_actions.length)
            end

            def context_menu_action_at(popup_box, row)
              context_menu_actions[row - popup_box.row - 1]
            end

            def adjusted_context_menu_row(anchor_row, popup_height, bounds_height)
              base_row = [anchor_row, 1].max
              max_row = [bounds_height - popup_height + 1, 1].max
              return base_row if base_row <= max_row

              [anchor_row - popup_height + 1, 1].max
            end

            def context_menu_action_enabled?(action_id)
              case action_id
              when :copy_to_clipboard
                translator_copy_available?
              when :paste_from_clipboard
                true
              else
                false
              end
            end

            def translator_copy_available?
              menu = translator_context_menu
              selection = translator_selection
              return false unless menu && selection
              return false unless selection[:pane].to_sym == menu[:pane].to_sym

              !selection_text(selection).empty?
            end
          end
        end
      end
    end
  end
end
