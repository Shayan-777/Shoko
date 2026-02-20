# frozen_string_literal: true

module Shoko
  module Presentation
    module Ui
      module Rendering
        module Models
          PageRenderingContext = Struct.new(
            :lines, :offset, :dimensions, :position, :show_page_num,
            keyword_init: true
          )

          FooterRenderingContext = Struct.new(
            :height, :width, :doc, :chapter, :pages, :view_mode, :mode,
            :line_spacing, :bookmarks,
            keyword_init: true
          )
        end
      end
    end
  end
end
