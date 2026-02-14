# frozen_string_literal: true

require_relative '../../../terminal/text_metrics'
require_relative 'config_helpers'
require_relative 'kitty_image_line_renderer'
require_relative 'line_content_composer'
require_relative 'line_geometry_builder'
require_relative 'rendered_lines_recorder'

module Shoko
  module Adapters::Output::Ui::Components
    module Reading
      # Draws a single line into a Surface and records its geometry.
      class LineDrawer
        def initialize(dependencies:, rendered_lines_buffer:, placed_kitty_images:, record_geometry: true)
          @dependencies = dependencies
          @record_geometry = record_geometry
          @content_composer = LineContentComposer.new
          if @record_geometry
            @geometry_builder = LineGeometryBuilder.new
            @recorder = RenderedLinesRecorder.new(buffer: rendered_lines_buffer, dependencies: dependencies)
          end
          @kitty_renderer = KittyImageLineRenderer.new(dependencies: dependencies,
                                                       placed_kitty_images: placed_kitty_images)
        end

        def draw_line(surface:, bounds:, line:, row:, col:, width:, context:, column_id:, line_offset:, page_id:)
          config_reader = resolve_config_reader(context)

          return if draw_kitty_line(surface: surface, bounds: bounds, line: line, row: row, col: col,
                                    context: context, config_reader: config_reader)

          _plain_text, styled_text = @content_composer.compose(line, width, config_reader)
          abs_row, abs_col = absolute_cell(bounds, row, col)
          clipped_styled, clipped_plain = clip_to_bounds(styled_text, width, bounds, abs_col)

          if @record_geometry
            geometry = @geometry_builder.build(page_id: page_id, column_id: column_id, row: abs_row, col: abs_col,
                                               line_offset: line_offset, plain_text: clipped_plain,
                                               styled_text: clipped_styled)
            @recorder.record(geometry)
          end
          surface.write(bounds, row, col, clipped_styled)
        end

        private

        def draw_kitty_line(surface:, bounds:, line:, row:, col:, context:, config_reader:)
          return false unless @kitty_renderer.kitty_image_line?(line, config: config_reader)

          image_text, col_offset = @kitty_renderer.render(line, context)
          return false if image_text.nil?
          return true if image_text.empty?

          surface.write(bounds, row, col + col_offset.to_i, image_text)
          true
        rescue StandardError
          false
        end

        def resolve_config_reader(context)
          context.config_reader if context.respond_to?(:config_reader)
        end

        def absolute_cell(bounds, row, col)
          [bounds.y + row - 1, bounds.x + col - 1]
        end

        def clip_to_bounds(styled_text, width, bounds, abs_col)
          max_width = [width.to_i, bounds.right - abs_col + 1].min
          max_width = 0 if max_width.negative?
          start_column = [abs_col - 1, 0].max

          clipped_styled = clipped_styled_text(styled_text, max_width, start_column)
          clipped_plain = Shoko::Adapters::Output::Terminal::TextMetrics.strip_ansi(clipped_styled)
          [clipped_styled, clipped_plain]
        end

        def clipped_styled_text(styled_text, max_width, start_column)
          return '' unless max_width.positive?

          Shoko::Adapters::Output::Terminal::TextMetrics.truncate_to(
            styled_text.to_s,
            max_width,
            start_column: start_column
          )
        end
      end
    end
  end
end
