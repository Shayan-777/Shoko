# frozen_string_literal: true

require_relative 'base_component'
require_relative 'status_bar/palette'
require_relative 'status_bar/progress_bar'
require_relative 'status_bar/bar_composer'
require 'shoko/shared/terminal/text_metrics'

module Shoko
  module Adapters
    module Ui
      module Components
        # The bottom status bar: a flat, full-width slate strip that adapts to the
        # current view. It draws a leading colored format/view badge, the primary
        # title with dimmed contextual details, and a right-aligned cluster with a
        # smooth progress bar, percentage, and position counters.
        #
        # It is purely a renderer: a +context_provider+ callable supplies a fresh
        # StatusContext each frame, so the same component serves the reader, the
        # menu, and any future view.
        class StatusBarComponent < BaseComponent
          Palette = StatusBar::Palette
          ProgressBar = StatusBar::ProgressBar
          BarComposer = StatusBar::BarComposer

          PROGRESS_CELLS = 12
          PROGRESS_MIN_WIDTH = 64

          def initialize(context_provider)
            super()
            @context_provider = context_provider
            @context = nil
          end

          # Occupy a single row only when there is something to show.
          def preferred_height(_available_height)
            @context = resolve_context
            renderable?(@context) ? 1 : 0
          end

          def do_render(surface, bounds)
            context = @context || resolve_context
            return unless renderable?(context)

            surface.write(bounds, 1, 1, build_line(context, bounds.width))
          ensure
            @context = nil
          end

          private

          def resolve_context
            @context_provider&.call
          end

          def renderable?(context)
            context && !context.empty?
          end

          def build_line(context, width)
            left = measured(build_left(context))
            right = measured(build_right(context, width))
            BarComposer.compose(width: width, left: left, right: right)
          end

          def measured(text)
            { text: text, width: Shoko::Shared::Terminal::TextMetrics.visible_length(text) }
          end

          # ----- left cluster: badge · title · details -----

          def build_left(context)
            # No leading pad: the badge/title snaps flush to the left edge (col 1).
            parts = []
            append_badge(parts, context.badge)
            append_title(parts, context.title)
            append_placeholder(parts, context)
            append_caret(parts, context)
            context.details.each { |detail| append_detail(parts, detail) }
            parts.join
          end

          def append_placeholder(parts, context)
            return unless context.title.to_s.empty? && !context.placeholder.to_s.empty?

            parts << Palette.span(context.placeholder, Palette::DIM_FG)
          end

          def append_caret(parts, context)
            return unless context.caret

            parts << "#{Palette::RESET}#{Palette::BAR_BG}#{Palette::CARET}"
          end

          def append_badge(parts, badge)
            return unless badge
            return append_mode_badge(parts, badge) if badge.mode

            face = "#{Palette::RESET}#{Palette.bg(badge.rgb)}#{Palette.fg(badge.fg)}#{Palette::BOLD}"
            pill = "#{face} #{badge.label} "
            parts << "#{pill}#{Palette::RESET}#{Palette::BAR_BG}" << pad
          end

          # Two compartments — a slate "mode" pill and the format-colored pill —
          # joined by a tilted slant whose colors interlock diagonally.
          def append_mode_badge(parts, badge)
            mode = "#{Palette::RESET}#{Palette.bg(Palette::BADGE_MODE_RGB)}#{Palette::BADGE_MODE_FG}" \
                   "#{Palette::BOLD} #{badge.mode} "
            slant = "#{Palette::RESET}#{Palette.bg(badge.rgb)}#{Palette.fg(Palette::BADGE_MODE_RGB)}" \
                    "#{Palette::BADGE_SLANT}"
            face = "#{Palette::RESET}#{Palette.bg(badge.rgb)}#{Palette.fg(badge.fg)}#{Palette::BOLD}"
            parts << mode << slant << "#{face} #{badge.label} #{Palette::RESET}#{Palette::BAR_BG}" << pad
          end

          def append_title(parts, title)
            text = title.to_s
            return if text.empty?

            parts << Palette.span(text, "#{Palette::BOLD}#{Palette::TITLE_FG}")
          end

          def append_detail(parts, detail)
            parts << separator << Palette.span(detail.to_s, Palette::TEXT_FG)
          end

          # ----- right cluster: progress · percent · counters -----

          def build_right(context, width)
            spans = []
            append_progress(spans, context, width)
            append_percent(spans, context)
            context.trailing.each { |item| append_trailing(spans, item, spans.empty?) }
            return '' if spans.empty?

            # No trailing pad: the counters snap flush to the right edge.
            spans.join
          end

          def append_progress(spans, context, width)
            return unless context.progress? && width >= PROGRESS_MIN_WIDTH

            bar = ProgressBar.render(
              fraction: context.progress,
              cells: PROGRESS_CELLS,
              fill_rgb: context.progress_rgb
            )
            spans << Palette.span('▕', Palette::FAINT_FG)
            spans << bar
            spans << "#{Palette::RESET}#{Palette::BAR_BG}#{Palette::FAINT_FG}▏"
          end

          def append_percent(spans, context)
            return unless context.progress?

            spans << separator unless spans.empty?
            spans << Palette.span("#{(context.progress * 100).round}%", Palette::DIM_FG)
          end

          def append_trailing(spans, item, first)
            spans << separator unless first
            spans << Palette.span(item.to_s, Palette::TEXT_FG)
          end

          # ----- shared bits -----

          def separator
            Palette.span(" #{Palette::SEPARATOR} ", Palette::DIM_FG)
          end

          def pad
            Palette.span(' ', Palette::TEXT_FG)
          end
        end
      end
    end
  end
end
