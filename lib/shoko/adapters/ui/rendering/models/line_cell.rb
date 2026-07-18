# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Rendering
        module Models
          # Represents a single rendered cell (grapheme cluster) within a line box.
          LineCell = Struct.new(:cluster, :char_start, :char_end, :display_width, :screen_x) do
            def visible?
              display_width.positive?
            end
          end
        end
      end
    end
  end
end
