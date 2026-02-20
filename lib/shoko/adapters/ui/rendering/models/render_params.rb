# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Rendering
        module Models
          # Parameter object to reduce long parameter lists in renderers.
          class RenderParams
            attr_reader :start_row, :col_start, :col_width, :context,
                        :line_offset, :column_id, :page_id

            def initialize(start_row:, col_start:, col_width:, context: nil,
                           line_offset: 0, column_id: 0, page_id: nil)
              @start_row = start_row
              @col_start = col_start
              @col_width = col_width
              @context = context
              @line_offset = line_offset
              @column_id = column_id
              @page_id = page_id
            end
          end
        end
      end
    end
  end
end
