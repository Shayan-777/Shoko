# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'
require_relative 'rect'
require_relative 'sidebar/tab_header_component'
require_relative 'sidebar/toc_tab_renderer'
require_relative 'sidebar/annotations_tab_renderer'
require_relative 'sidebar/bookmarks_tab_renderer'
require_relative 'ui/text_utils'
require_relative '../../../../core/services/layout_service'

module Shoko
  module Adapters::Output::Ui::Components
    # Collapsible sidebar panel with tabbed interface for TOC, Annotations, and Bookmarks
    class SidebarPanelComponent < BaseComponent
      include Adapters::Output::Ui::Constants::UI

      TABS = %i[toc annotations bookmarks].freeze
      TAB_TITLES = { toc: 'Contents', annotations: 'Annotations', bookmarks: 'Bookmarks' }.freeze
      TAB_KEYS = { toc: 'T', annotations: 'A', bookmarks: 'B' }.freeze
      HELP_TEXTS = {
        toc: '↑↓ Navigate • ⏎ Jump • Space Toggle • / Filter',
        annotations: '↑↓ Navigate • ⏎ Jump • e Edit • d Delete',
        bookmarks: '↑↓ Navigate • ⏎ Jump • d Delete',
      }.freeze
      DEFAULT_WIDTH_PERCENT = Shoko::Core::Services::LayoutService::SIDEBAR_WIDTH_PERCENT
      MIN_WIDTH = Shoko::Core::Services::LayoutService::SIDEBAR_MIN_WIDTH
      HEADER_HEIGHT = 2
      TAB_HEIGHT = 3
      HELP_HEIGHT = 1

      def initialize(state, dependencies)
        super() # Call BaseComponent constructor
        @state = state
        @dependencies = dependencies
        @tab_header = Sidebar::TabHeaderComponent.new(state, dependencies: dependencies)
        @toc_renderer = Sidebar::TocTabRenderer.new(state, dependencies)
        @annotations_renderer = Sidebar::AnnotationsTabRenderer.new(state)
        @bookmarks_renderer = Sidebar::BookmarksTabRenderer.new(state, dependencies)
        @reader_state_reader = nil

        # Observe sidebar state changes
        state.add_observer(self,
                           %i[reader sidebar_visible],
                           %i[reader sidebar_active_tab],
                           %i[reader sidebar_toc_selected],
                           %i[reader sidebar_toc_collapsed],
                           %i[reader sidebar_annotations_selected],
                           %i[reader sidebar_bookmarks_selected])
      end

      def preferred_width(total_width)
        return :hidden unless reader_state_reader&.sidebar_visible?

        Shoko::Core::Services::LayoutService.sidebar_width(total_width)
      end

      def do_render(surface, bounds)
        bw = bounds.width
        bh = bounds.height
        return unless reader_state_reader&.sidebar_visible? && bw >= MIN_WIDTH

        # Cache frequently-used bounds values
        bx = bounds.x
        by = bounds.y
        # bw, bh already cached above

        # Draw modern border
        draw_border(surface, bounds)

        content_bounds = content_bounds_for(bounds)
        return unless content_bounds

        # Render minimal header with title only
        header_bounds = Rect.new(x: bx, y: by, width: bw,
                                 height: HEADER_HEIGHT)
        render_header(surface, header_bounds)

        # Render active tab content
        render_active_tab(surface, content_bounds)

        # Render help text
        help_bounds = Rect.new(
          x: bx,
          y: content_bounds.y + content_bounds.height,
          width: bw,
          height: HELP_HEIGHT
        )
        render_help(surface, help_bounds)

        # Render tab navigation at bottom
        tab_bounds = Rect.new(
          x: bx,
          y: by + bh - TAB_HEIGHT,
          width: bw,
          height: TAB_HEIGHT
        )
        @tab_header.render(surface, tab_bounds)
      end

      def sidebar_bounds_for(total_width, total_height)
        return nil unless @reader_state_reader&.sidebar_visible?

        width = preferred_width(total_width)
        return nil unless width.is_a?(Integer) && width.positive?

        width = [width, total_width].min
        Rect.new(x: 1, y: 1, width: width, height: total_height)
      end

      def tab_for_point(col, row, sidebar_bounds)
        return nil unless sidebar_bounds

        tab_bounds = tab_bounds_for(sidebar_bounds)
        @tab_header.tab_for_point(tab_bounds, col, row)
      end

      def toc_entry_at(col, row, sidebar_bounds)
        return nil unless sidebar_bounds

        active_tab = reader_state_reader&.sidebar_active_tab || :toc
        return nil unless active_tab == :toc

        content_bounds = content_bounds_for(sidebar_bounds)
        return nil unless content_bounds

        @toc_renderer.entry_at(content_bounds, col, row)
      end

      def toc_scroll_metrics(sidebar_bounds)
        return nil unless sidebar_bounds

        active_tab = reader_state_reader&.sidebar_active_tab || :toc
        return nil unless active_tab == :toc

        content_bounds = content_bounds_for(sidebar_bounds)
        return nil unless content_bounds

        @toc_renderer.scroll_metrics(content_bounds)
      end

      private

      def draw_border(surface, bounds)
        # Draw modern vertical border on the right edge
        h = bounds.height
        w = bounds.width
        reset = Terminal::ANSI::RESET
        dim = COLOR_TEXT_DIM
        (1..h).each do |y|
          surface.write(bounds, y, w, "#{dim}│#{reset}")
        end
      end

      def render_header(surface, bounds)
        # Simple clean title
        active_tab = reader_state_reader&.sidebar_active_tab || :toc
        title = TAB_TITLES[active_tab] || 'Sidebar'
        reset = Terminal::ANSI::RESET
        surface.write(bounds, 1, 2, "#{SELECTION_HIGHLIGHT}#{title}#{reset}")

        # Close indicator
        w = bounds.width
        key = TAB_KEYS[active_tab] || 'T'
        close_text = "#{COLOR_TEXT_DIM}[#{key}]#{reset}"
        surface.write(bounds, 1, w - 5, close_text)
      end

      def render_help(surface, bounds)
        active_tab = reader_state_reader&.sidebar_active_tab || :toc
        reset = Terminal::ANSI::RESET
        width = bounds.width
        hint = HELP_TEXTS[active_tab]
        return unless hint

        max_hint_width = [width - 4, 1].max
        clipped_hint = UI::TextUtils.truncate_text(hint, max_hint_width)
        surface.write(bounds, 1, 2, "#{COLOR_TEXT_DIM}#{clipped_hint}#{reset}")
      end

      def render_active_tab(surface, bounds)
        active_tab = reader_state_reader&.sidebar_active_tab || :toc
        renderer = { toc: @toc_renderer, annotations: @annotations_renderer,
                     bookmarks: @bookmarks_renderer }[active_tab]
        renderer&.render(surface, bounds)
      end

      def reader_state_reader
        return @reader_state_reader if @reader_state_reader

        @reader_state_reader = @dependencies&.resolve(:reader_state_reader)
      rescue StandardError
        nil
      end

      def content_bounds_for(bounds)
        content_height = bounds.height - HEADER_HEIGHT - TAB_HEIGHT - HELP_HEIGHT
        return nil if content_height <= 0

        Rect.new(
          x: bounds.x,
          y: bounds.y + HEADER_HEIGHT,
          width: bounds.width,
          height: content_height
        )
      end

      def tab_bounds_for(sidebar_bounds)
        Rect.new(
          x: sidebar_bounds.x,
          y: sidebar_bounds.y + sidebar_bounds.height - TAB_HEIGHT,
          width: sidebar_bounds.width,
          height: TAB_HEIGHT
        )
      end
    end
  end
end
