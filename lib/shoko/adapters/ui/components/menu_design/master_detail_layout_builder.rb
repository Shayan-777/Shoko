# frozen_string_literal: true

require_relative '../rect'
require_relative 'layout'

module Shoko
  module Adapters
    module Ui
      module Components
        module MenuDesign
          # Computes the shared menu shell geometry for list + inspector screens.
          class MasterDetailLayoutBuilder
            Panel = Data.define(:frame, :content)
            ShellLayout = Data.define(
              :shell_indent,
              :shell_width,
              :summary_row,
              :prelude_top,
              :prelude_rows,
              :panels_top,
              :panels_height,
              :primary_panel,
              :secondary_panel,
              :wide_split,
              :stacked_detail,
              :footer_row
            )

            SHELL_PREFERRED_WIDTH = 108
            SHELL_MIN_WIDTH = 52
            SHELL_HORIZONTAL_PADDING = 8
            SUMMARY_ROW = 3
            PRELUDE_TOP = 4
            DETAIL_GAP = 4
            DEFAULT_DETAIL_WIDTH = 30
            MIN_DETAIL_WIDTH = 28
            MIN_PRIMARY_WIDTH = 34
            MIN_PANEL_HEIGHT = 6
            DEFAULT_STACKED_DETAIL_HEIGHT = 9
            STACKED_PANEL_GAP = 1
            DEFAULT_PANEL_OPTIONS = {
              desired_detail_width: DEFAULT_DETAIL_WIDTH,
              min_primary_width: MIN_PRIMARY_WIDTH,
              min_detail_width: MIN_DETAIL_WIDTH,
              stacked_detail_height: DEFAULT_STACKED_DETAIL_HEIGHT,
              preferred_width: SHELL_PREFERRED_WIDTH,
            }.freeze

            def initialize(bounds)
              @bounds = bounds
            end

            def build(prelude_rows: 0, detail_visible: true, **panel_options)
              shell_width = centered_shell_width(resolved_panel_options(panel_options).fetch(:preferred_width))
              prelude_count = [prelude_rows.to_i, 0].max
              metrics = shell_metrics(shell_width, prelude_count)
              panels = build_panels(**metrics, detail_visible: detail_visible, **resolved_panel_options(panel_options))

              build_shell_layout(**metrics, prelude_count: prelude_count, panels: panels)
            end

            private

            def centered_shell_width(preferred_width)
              Layout.centered_content_width(
                @bounds,
                preferred: preferred_width,
                min: SHELL_MIN_WIDTH,
                horizontal_padding: SHELL_HORIZONTAL_PADDING
              )
            end

            def vertical_metrics(prelude_count)
              footer_row = @bounds.height - 1
              panels_top = PRELUDE_TOP + prelude_count + 1
              panels_height = [footer_row - panels_top, 1].max
              [footer_row, panels_top, panels_height]
            end

            def shell_metrics(shell_width, prelude_count)
              footer_row, panels_top, panels_height = vertical_metrics(prelude_count)
              {
                shell_indent: Layout.centered_indent(@bounds, shell_width),
                shell_width: shell_width,
                panels_top: panels_top,
                panels_height: panels_height,
                footer_row: footer_row,
              }
            end

            def resolved_panel_options(panel_options)
              DEFAULT_PANEL_OPTIONS.merge(panel_options)
            end

            def build_panels(shell_indent:, shell_width:, panels_top:, panels_height:, detail_visible:, **panel_options)
              geometry = {
                shell_indent: shell_indent,
                shell_width: shell_width,
                panels_top: panels_top,
                panels_height: panels_height,
              }
              wide_frames = wide_panel_frames(geometry, detail_visible, panel_options)
              return materialize_panel_frames(wide_frames, wide_split: true) if wide_frames

              stacked_frames = stacked_panel_frames(
                geometry,
                detail_visible,
                panel_options.fetch(:stacked_detail_height)
              )
              return materialize_panel_frames(stacked_frames, wide_split: false) if stacked_frames

              primary_only_panel(shell_indent, panels_top, shell_width, panels_height)
            end

            def wide_panel_frames(geometry, detail_visible, panel_options)
              return unless detail_visible && geometry[:panels_height] >= MIN_PANEL_HEIGHT

              detail_width = wide_detail_width(geometry, panel_options)
              return unless detail_width

              primary_width = geometry[:shell_width] - detail_width - DETAIL_GAP
              return if primary_width < panel_options.fetch(:min_primary_width)

              wide_frames(geometry, primary_width, detail_width)
            end

            def wide_detail_width(geometry, panel_options)
              resolve_detail_width(
                geometry[:shell_width],
                panel_options.fetch(:desired_detail_width),
                panel_options.fetch(:min_primary_width),
                panel_options.fetch(:min_detail_width)
              )
            end

            def wide_frames(geometry, primary_width, detail_width)
              primary_frame = panel_frame(
                geometry[:shell_indent],
                geometry[:panels_top],
                primary_width,
                geometry[:panels_height]
              )
              secondary_frame = panel_frame(
                geometry[:shell_indent] + primary_width + DETAIL_GAP,
                geometry[:panels_top],
                detail_width,
                geometry[:panels_height]
              )
              [primary_frame, secondary_frame]
            end

            def resolve_detail_width(shell_width, desired_detail_width, min_primary_width, min_detail_width)
              available_detail_width = shell_width - min_primary_width - DETAIL_GAP
              return if available_detail_width < min_detail_width

              desired_detail_width.to_i.clamp(min_detail_width, available_detail_width)
            end

            def stacked_panel_frames(geometry, detail_visible, stacked_detail_height)
              return unless detail_visible

              max_detail_height = geometry[:panels_height] - MIN_PANEL_HEIGHT - STACKED_PANEL_GAP
              return if max_detail_height < MIN_PANEL_HEIGHT

              detail_height = stacked_detail_height.to_i.clamp(MIN_PANEL_HEIGHT, max_detail_height)
              primary_height = geometry[:panels_height] - detail_height - STACKED_PANEL_GAP
              return if primary_height < MIN_PANEL_HEIGHT

              stacked_frames(geometry, primary_height, detail_height)
            end

            def stacked_frames(geometry, primary_height, detail_height)
              primary_frame = panel_frame(
                geometry[:shell_indent],
                geometry[:panels_top],
                geometry[:shell_width],
                primary_height
              )
              secondary_frame = panel_frame(
                geometry[:shell_indent],
                geometry[:panels_top] + primary_height + STACKED_PANEL_GAP,
                geometry[:shell_width],
                detail_height
              )
              [primary_frame, secondary_frame]
            end

            def materialize_panel_frames(frames, wide_split:)
              primary_frame, secondary_frame = frames
              [panel_from_frame(primary_frame), panel_from_frame(secondary_frame), wide_split, !wide_split]
            end

            def primary_only_panel(shell_indent, panels_top, shell_width, panels_height)
              primary_frame = panel_frame(shell_indent, panels_top, shell_width, panels_height)
              [panel_from_frame(primary_frame), nil, false, false]
            end

            def panel_frame(pos_x, pos_y, width, height)
              Rect.new(x: pos_x, y: pos_y, width: width, height: height)
            end

            def build_shell_layout(shell_indent:, shell_width:, prelude_count:, panels_top:, panels_height:,
                                   footer_row:, panels:)
              primary_panel, secondary_panel, wide_split, stacked_detail = panels
              ShellLayout.new(
                shell_indent: shell_indent,
                shell_width: shell_width,
                summary_row: SUMMARY_ROW,
                prelude_top: PRELUDE_TOP,
                prelude_rows: prelude_count,
                panels_top: panels_top,
                panels_height: panels_height,
                primary_panel: primary_panel,
                secondary_panel: secondary_panel,
                wide_split: wide_split,
                stacked_detail: stacked_detail,
                footer_row: footer_row
              )
            end

            def panel_from_frame(frame)
              content_height = [frame.height - 1, 1].max
              Panel.new(
                frame: frame,
                content: Rect.new(x: frame.x, y: frame.y + 1, width: frame.width, height: content_height)
              )
            end
          end
        end
      end
    end
  end
end
