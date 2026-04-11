# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../../shared/terminal/ansi'
require_relative '../../../../shared/terminal/text_metrics'
require_relative '../menu_design/frame_renderer'
require_relative '../menu_design/layout'
require_relative '../menu_design/status_renderer'
require_relative '../menu_design/theme_tokens'
require_relative '../ui/box_drawer'
require_relative '../ui/list_helpers'
require_relative '../ui/text_utils'
require_relative 'rss_reader_screen_component/layout_support'
require_relative 'rss_reader_screen_component/state_support'
require_relative 'rss_reader_screen_component/status_support'
require_relative 'rss_reader_screen_component/list_support'
require_relative 'rss_reader_screen_component/content_support'
require_relative 'rss_reader_screen_component/overlay_support'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Three-pane RSS workspace with feed list, headline list, and article reader.
          class RssReaderScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::BoxDrawer
            include Ui::TextUtils
            include RssReaderScreenComponentLayoutSupport
            include RssReaderScreenComponentStateSupport
            include RssReaderScreenComponentStatusSupport
            include RssReaderScreenComponentListSupport
            include RssReaderScreenComponentContentSupport
            include RssReaderScreenComponentOverlaySupport

            MIN_FEED_WIDTH = 24
            MAX_FEED_WIDTH = 30
            MIN_ARTICLE_HEIGHT = 7
            BOX_GAP = 2
            ROW_GAP = 1
            OVERLAY_HEIGHT = 5
            OVERLAY_WIDTH = 60
            FEED_BADGE_WIDTH = 7
            ARTICLE_DATE_WIDTH = 16
            ALL_FEEDS_KEY = '__all__'

            def initialize(dependencies: nil, menu_visual_profile: nil)
              super()
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
              @tokens = MenuDesign::ThemeTokens.new
            end

            def do_render(surface, bounds)
              layout = layout_metrics(bounds)
              frame = MenuDesign::FrameRenderer.new(surface, bounds, tokens: @tokens)
              frame.render_title(title: 'RSS Reader', hint: header_hint)
              frame.render_divider
              render_status_row(surface, bounds, layout)
              render_workspace(surface, bounds, layout)
              render_prompt_overlay(surface, bounds, layout) if overlay_mode?
              frame.render_footer(text: footer_text)
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def render_workspace(surface, bounds, layout)
              return render_empty_workspace(surface, bounds, layout) if feed_entries.empty?

              if zen_mode?
                render_zen_workspace(surface, bounds, layout)
              else
                render_standard_workspace(surface, bounds, layout)
              end
            end

            def render_empty_workspace(surface, bounds, layout)
              box = Ui::BoxDrawer::BoxSpec.new(layout[:workspace_top], layout[:indent], layout[:workspace_height],
                                               layout[:content_width])
              draw_box(surface, bounds, box, label: 'Reader', border_color: BORDER_PRIMARY, label_color: @tokens.accent)
              render_box_empty(
                surface,
                bounds,
                box,
                'No feeds configured yet. Press A to add a feed URL and S to sync.'
              )
            end

            def render_standard_workspace(surface, bounds, layout)
              render_feed_pane(surface, bounds, layout[:feed_box])
              render_article_pane(surface, bounds, layout[:article_box])
              render_content_pane(surface, bounds, layout[:content_box])
            end

            def render_zen_workspace(surface, bounds, layout)
              box = Ui::BoxDrawer::BoxSpec.new(layout[:workspace_top], layout[:indent], layout[:workspace_height],
                                               layout[:content_width])
              draw_box(
                surface,
                bounds,
                box,
                label: zen_box_label,
                border_color: pane_border_color(:content),
                label_color: pane_label_color(:content)
              )
              render_content_body(surface, bounds, box, selected_article_hash)
            end
          end
        end
      end
    end
  end
end
