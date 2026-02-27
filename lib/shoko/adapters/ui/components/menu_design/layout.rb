# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module MenuDesign
          # Shared layout math for centered menu content blocks.
          module Layout
            module_function

            def centered_content_width(bounds, preferred:, min: 24, horizontal_padding: 6)
              width = [bounds.width - horizontal_padding, preferred].min
              [[width, min].max, [bounds.width - 2, min].max].min
            end

            def centered_indent(bounds, content_width, min: 2)
              indent = ((bounds.width - content_width) / 2).floor
              indent.clamp(min, [bounds.width - content_width, min].max)
            end

            def centered_row(bounds, top:, bottom:, content_rows:)
              return top if content_rows <= 0

              row = (bounds.height - content_rows) / 2
              row.clamp(top, [bottom - content_rows, top].max)
            end
          end
        end
      end
    end
  end
end
