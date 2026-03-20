# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        # Positioning helpers for anchored and selection-derived popup placement.
        module EnhancedPopupMenuPositioningHelpers
          private

          def apply_popup_position(anchor_position:)
            position = popup_position_for(anchor_position: anchor_position)
            @x = position[:x]
            @y = position[:y]
          end

          def popup_position_for(anchor_position:)
            return explicit_anchor_popup_position(anchor_position) if anchor_position

            popup_anchor_position(@selection_range[:end])
          end

          def explicit_anchor_popup_position(anchor_position)
            anchor = normalize_anchor_position(anchor_position)
            calculate_popup_position(x_pos: anchor[:x], y_pos: anchor[:y])
          end

          def popup_anchor_position(anchor_hash)
            anchor = Shoko::Core::Models::SelectionAnchor.from(anchor_hash)
            geometry = geometry_for_anchor(anchor)
            return { x: 1, y: 1 } unless geometry

            calculate_popup_position(x_pos: anchor_column_position(anchor, geometry), y_pos: geometry.row)
          end

          def anchor_column_position(anchor, geometry)
            return geometry.column_origin + geometry.visible_width if anchor.cell_index >= geometry.cells.length

            geometry.column_origin + geometry.cells[anchor.cell_index].screen_x
          end

          def normalize_anchor_position(anchor)
            normalized = anchor.transform_keys do |key|
              key.is_a?(String) ? key.to_sym : key
            end
            {
              x: (normalized[:x] || 1).to_i,
              y: (normalized[:y] || 1).to_i,
            }
          end

          def geometry_for_anchor(anchor)
            return nil unless anchor && @rendered_lines

            entry = @rendered_lines[anchor.geometry_key]
            entry && entry[:geometry]
          end

          def calculate_popup_position(x_pos:, y_pos:)
            anchor = { x: x_pos, y: y_pos }
            return popup_position_from_service(anchor) if @popup_position_service
            return @coordinate_service.calculate_popup_position(anchor, @width, @height) if @coordinate_service

            { x: 1, y: 1 }
          end

          def popup_position_from_service(anchor)
            @popup_position_service.calculate_popup_position(anchor, @width, @height)
          end
        end
      end
    end
  end
end
