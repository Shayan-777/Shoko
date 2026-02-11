# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../../terminal/text_metrics'

module Shoko
  module Adapters::Output::Ui::Components
    module Sidebar
      # Modern bottom tab navigation for sidebar
      class TabHeaderComponent < BaseComponent
        include Adapters::Output::Ui::Constants::UI

        RenderTarget = Struct.new(:surface, :bounds, keyword_init: true) do
          def write(row, col, text)
            surface.write(bounds, row, col, text)
          end
        end
        private_constant :RenderTarget

        TABS = %i[toc annotations bookmarks].freeze
        TAB_INFO = {
          toc: { label: 'Contents', icon: '◉', key: 'T' },
          annotations: { label: 'Notes', icon: '◈', key: 'A' },
          bookmarks: { label: 'Bookmarks', icon: '◆', key: 'B' },
        }.freeze

        def initialize(state, dependencies: nil)
          super() # Call BaseComponent constructor with no services
          @state = state
          @dependencies = dependencies
          @reader_state_reader = nil
        end

        def do_render(surface, bounds)
          target = RenderTarget.new(surface: surface, bounds: bounds)
          draw_separator(target)
          render_tab_navigation(target)
        end

        def tab_for_point(bounds, col, row)
          return nil unless bounds

          local_row = row.to_i - bounds.y + 1
          local_col = col.to_i - bounds.x + 1
          return nil unless local_row.between?(2, 3)
          return nil unless local_col.between?(1, bounds.width)

          tab_width = (bounds.width - 2) / TABS.length
          return nil if tab_width <= 0

          offset = local_col - 2
          return nil if offset.negative?

          max_tabs_width = tab_width * TABS.length
          return nil if offset >= max_tabs_width

          TABS[offset / tab_width]
        end

        # Internal context for rendering a single tab button.
        TabButtonCtx = Struct.new(
          :tab,
          :x,
          :width,
          :active,
          :icon,
          :label,
          :key,
          :row_top,
          :row_bottom,
          keyword_init: true
        )
        private_constant :TabButtonCtx

        private

        def draw_separator(target)
          width = target.bounds.width
          line_width = [width - 1, 0].max
          return if line_width.zero?

          reset = Terminal::ANSI::RESET
          target.write(1, 1, "#{COLOR_TEXT_DIM}#{'─' * line_width}#{reset}")
          junction_col = width
          target.write(1, junction_col, "#{COLOR_TEXT_DIM}┤#{reset}") if junction_col.positive?
        end

        def render_tab_navigation(target)
          tab_width = (target.bounds.width - 2) / TABS.length
          row_top = 2
          row_bottom = 3

          active_tab = reader_state_reader&.sidebar_active_tab || :toc
          TABS.each_with_index do |tab, index|
            x_pos = 2 + (index * tab_width)
            active = (active_tab == tab)
            ctx = build_tab_button_ctx(tab, x_pos, tab_width, active, row_top: row_top, row_bottom: row_bottom)
            render_tab_button(target, ctx)
          end
        end

        def reader_state_reader
          return @reader_state_reader if @reader_state_reader

          @reader_state_reader = @dependencies&.reader_state_reader
        end

        def build_tab_button_ctx(tab, x_pos, width, active, row_top:, row_bottom:)
          info = TAB_INFO.fetch(tab)
          TabButtonCtx.new(
            tab: tab,
            x: x_pos,
            width: width,
            active: active,
            icon: info[:icon],
            label: info[:label],
            key: info[:key],
            row_top: row_top,
            row_bottom: row_bottom
          )
        end

        def render_tab_button(target, ctx)
          ctx.active ? render_active(target, ctx) : render_inactive(target, ctx)
        end

        def render_active(target, ctx)
          reset = Terminal::ANSI::RESET
          icon_text = "#{COLOR_TEXT_ACCENT}#{ctx.icon}#{reset}"
          label_text = "#{COLOR_TEXT_PRIMARY}#{ctx.label}#{reset}"

          content = "#{ctx.icon} #{ctx.label}"
          content_len = Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(content)
          padding = [(ctx.width - content_len) / 2, 0].max
          padded_col = ctx.x + padding

          target.write(ctx.row_top, padded_col, icon_text)
          target.write(ctx.row_top, padded_col + 2, label_text)
          render_active_indicator(target, ctx, content_len, reset)
        end

        def render_active_indicator(target, ctx, content_len, reset)
          indicator_width = [content_len, ctx.width - 2].min
          return if indicator_width <= 0

          start = ctx.x + [(ctx.width - indicator_width) / 2, 0].max
          line = "#{COLOR_TEXT_ACCENT}#{'▬' * indicator_width}#{reset}"
          target.write(ctx.row_bottom, start, line)
        end

        def render_inactive(target, ctx)
          reset = Terminal::ANSI::RESET
          icon_text = "#{COLOR_TEXT_DIM}#{ctx.icon}#{reset}"
          key_hint = "#{COLOR_TEXT_DIM}[#{ctx.key}]#{reset}"

          icon_padding = [(ctx.width - 1) / 2, 0].max
          target.write(ctx.row_top, ctx.x + icon_padding, icon_text)

          key_padding = [(ctx.width - 3) / 2, 0].max
          target.write(ctx.row_bottom, ctx.x + key_padding, key_hint)
        end
      end
    end
  end
end
