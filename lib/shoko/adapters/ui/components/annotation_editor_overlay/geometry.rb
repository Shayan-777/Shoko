# frozen_string_literal: true

module Shoko
  module Adapters::Ui::Components
    # Namespace for annotation editor overlay helpers.
    module AnnotationEditorOverlay
      # Geometry helper for the annotation editor overlay content region.
      class Geometry
        attr_reader :layout

        def initialize(layout)
          @layout = layout
        end

        def content_x
          layout.inner_x + 2
        end

        def content_width
          [layout.inner_width - 4, 1].max
        end

        def header_row
          layout.inner_y + 1
        end

        def subheader_row
          header_row + 1
        end

        def label_row
          subheader_row + 2
        end

        def note_top
          label_row + 1
        end

        def note_rows
          [buttons_row - note_top, 1].max
        end

        def text_x
          content_x
        end

        def text_width
          content_width
        end

        def buttons_row
          layout.inner_y + layout.inner_height - 2
        end

        def button_row_abs(bounds)
          bounds.y + buttons_row - 1
        end
      end
    end
  end
end
