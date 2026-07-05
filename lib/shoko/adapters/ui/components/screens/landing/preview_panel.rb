# frozen_string_literal: true

require_relative '../../menu_design/canvas_frame'
require_relative 'preview'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          module Landing
            # The landing menu's preview canvas: the highlighted rail entry's
            # live preview rendered in the shared canvas grammar — hairline
            # rule with the accent-colored title, body rows on the elevated
            # slate, and a dim hint resting on the bottom row.
            class PreviewPanel
              def initialize(surface, bounds)
                @frame = MenuDesign::CanvasFrame.new(surface, bounds)
                @surface = surface
                @bounds = bounds
              end

              def render(preview)
                @frame.paint
                return if @frame.content_width < 8

                @frame.render_rule(title: preview.title, meta: preview.meta, accent: preview.accent_fg)
                render_lines(preview.lines)
                @frame.render_hint(preview.hint)
              end

              private

              def render_lines(lines)
                row = @frame.body_top
                Array(lines).each do |line|
                  break if row > @frame.body_bottom

                  @surface.write(@bounds, row, @frame.content_x,
                                 @frame.compose(left: line.left, right: line.right))
                  row += 1
                end
              end
            end
          end
        end
      end
    end
  end
end
