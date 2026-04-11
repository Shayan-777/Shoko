# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Layout helpers for the three-pane RSS reader screen.
          module RssReaderScreenComponentLayoutSupport
            private

            def layout_metrics(bounds)
              content_width = MenuDesign::Layout.centered_content_width(bounds, preferred: 98, min: 48,
                                                                                horizontal_padding: 4)
              dimensions = workspace_dimensions(bounds, content_width)
              layout_metadata(content_width, dimensions).merge(workspace_boxes(dimensions))
            end

            def feed_width_for(content_width)
              (content_width * 0.28).floor.clamp(self.class::MIN_FEED_WIDTH, self.class::MAX_FEED_WIDTH)
            end

            def article_height_for(workspace_height)
              max_height = [workspace_height - 4, self.class::MIN_ARTICLE_HEIGHT].max
              (workspace_height * 0.38).floor.clamp(self.class::MIN_ARTICLE_HEIGHT, max_height)
            end

            def workspace_dimensions(bounds, content_width)
              workspace_top = 6
              workspace_height = [bounds.height - workspace_top - 2, 8].max
              feed_width = feed_width_for(content_width)
              article_height = article_height_for(workspace_height)

              {
                indent: MenuDesign::Layout.centered_indent(bounds, content_width),
                workspace_top: workspace_top,
                workspace_height: workspace_height,
                feed_width: feed_width,
                right_width: [content_width - feed_width - self.class::BOX_GAP, 18].max,
                article_height: article_height,
                content_height: [workspace_height - article_height - self.class::ROW_GAP, 3].max,
              }
            end

            def layout_metadata(content_width, dimensions)
              {
                indent: dimensions[:indent],
                content_width: content_width,
                status_row: 4,
                workspace_top: dimensions[:workspace_top],
                workspace_height: dimensions[:workspace_height],
              }
            end

            def workspace_boxes(dimensions)
              {
                feed_box: feed_box(dimensions),
                article_box: article_box(dimensions),
                content_box: content_box(dimensions),
              }
            end

            def feed_box(dimensions)
              Ui::BoxDrawer::BoxSpec.new(
                dimensions[:workspace_top],
                dimensions[:indent],
                dimensions[:workspace_height],
                dimensions[:feed_width]
              )
            end

            def article_box(dimensions)
              Ui::BoxDrawer::BoxSpec.new(
                dimensions[:workspace_top],
                dimensions[:indent] + dimensions[:feed_width] + self.class::BOX_GAP,
                dimensions[:article_height],
                dimensions[:right_width]
              )
            end

            def content_box(dimensions)
              Ui::BoxDrawer::BoxSpec.new(
                dimensions[:workspace_top] + dimensions[:article_height] + self.class::ROW_GAP,
                dimensions[:indent] + dimensions[:feed_width] + self.class::BOX_GAP,
                dimensions[:content_height],
                dimensions[:right_width]
              )
            end
          end
        end
      end
    end
  end
end
