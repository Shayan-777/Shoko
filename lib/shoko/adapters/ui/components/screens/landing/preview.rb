# frozen_string_literal: true

require_relative '../../menu_design/view_accents'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          module Landing
            # Render-ready preview for one menu entry: the rule title and meta,
            # the entry's signature accent, the body lines, and the hint that
            # sits on the canvas's bottom row. Lines are segment lists so the
            # panel can lay every row onto the canvas surface uniformly.
            Preview = Data.define(:title, :meta, :accent_fg, :lines, :hint)

            # One canvas row: +left+ segments flow from the left inset, +right+
            # segments are right-aligned against the canvas edge; each segment
            # is a [text, foreground] pair (nil foreground = body tone). The
            # gap between the two clusters stays on the canvas surface.
            PreviewLine = Data.define(:left, :right) do
              def self.blank
                new(left: [], right: [])
              end

              def self.text(text, foreground = nil, right: [])
                new(left: [[text, foreground]], right: right)
              end
            end

            # The per-view signature accents live with the rest of the design
            # kit; landing code keeps its historical short name.
            Accents = MenuDesign::ViewAccents
          end
        end
      end
    end
  end
end
