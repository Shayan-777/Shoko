# frozen_string_literal: true

require_relative '../../../../shared/terminal/text_metrics'
require_relative 'config_helpers'
require_relative 'kitty_image_line_renderer'
require_relative 'line_content_composer'
require_relative 'line_geometry_builder'
require_relative 'rendered_lines_recorder'

module Shoko
  module Adapters
    module Ui
      module Components
        module Reading
          # Draws a single line into a Surface and records its geometry.
          class LineDrawer
            DrawRequest = Data.define(
              :line,
              :row,
              :col,
              :width,
              :config_reader,
              :hovered_inline_link,
              :column_id,
              :line_offset,
              :page_id
            )
            PreparedLine = Data.define(:abs_row, :abs_col, :clipped_styled, :clipped_plain)

            def initialize(dependencies:, rendered_lines_buffer:, placed_kitty_images:, record_geometry: true)
              @dependencies = dependencies
              @record_geometry = record_geometry
              runtime_config = @dependencies&.runtime_config
              @content_composer = LineContentComposer.new(runtime_config: runtime_config)
              if @record_geometry
                @geometry_builder = LineGeometryBuilder.new(runtime_config: runtime_config)
                @recorder = RenderedLinesRecorder.new(buffer: rendered_lines_buffer, dependencies: dependencies)
              end
              @kitty_renderer = KittyImageLineRenderer.new(dependencies: dependencies,
                                                           placed_kitty_images: placed_kitty_images)
            end

            def draw_line(surface:, bounds:, line:, row:, col:, width:, context:, column_id:, line_offset:, page_id:)
              config_reader, hovered_inline_link = compose_context(context)
              return if draw_kitty_line?(surface: surface, bounds: bounds, line: line, row: row, col: col,
                                         context: context, config_reader: config_reader)

              request = DrawRequest.new(
                line: line,
                row: row,
                col: col,
                width: width,
                config_reader: config_reader,
                hovered_inline_link: hovered_inline_link,
                column_id: column_id,
                line_offset: line_offset,
                page_id: page_id
              )
              draw_prepared_line(surface: surface, bounds: bounds, request: request)
            end

            private

            def draw_kitty_line?(surface:, bounds:, line:, row:, col:, context:, config_reader:)
              return false unless @kitty_renderer.kitty_image_line?(line, config: config_reader)

              image_text, col_offset = @kitty_renderer.render(line, context)
              return false if image_text.nil?
              return true if image_text.empty?

              surface.write(bounds, row, col + col_offset.to_i, image_text)
              true
            end

            def resolve_config_reader(context)
              context&.config_reader
            end

            def compose_context(context)
              [resolve_config_reader(context), hovered_inline_link_for(context)]
            end

            def hovered_inline_link_for(context)
              reader_state_reader = context&.reader_state_reader
              return unless reader_state_reader.respond_to?(:hovered_inline_link)

              reader_state_reader.hovered_inline_link
            end

            def absolute_cell(bounds, row, col)
              [bounds.y + row - 1, bounds.x + col - 1]
            end

            def draw_prepared_line(surface:, bounds:, request:)
              prepared_line = prepared_line_for(bounds, request)
              record_line_geometry_for_request(prepared_line, request)
              surface.write(bounds, request.row, request.col, prepared_line.clipped_styled)
            end

            def prepared_line_for(bounds, request)
              prepare_line_output(
                bounds: bounds,
                col: request.col,
                config_reader: request.config_reader,
                hovered_inline_link: request.hovered_inline_link,
                line: request.line,
                line_offset: request.line_offset,
                row: request.row,
                width: request.width
              )
            end

            def record_line_geometry_for_request(prepared_line, request)
              record_line_geometry(
                prepared_line,
                column_id: request.column_id,
                line: request.line,
                line_offset: request.line_offset,
                page_id: request.page_id
              )
            end

            def prepare_line_output(bounds:, col:, config_reader:, hovered_inline_link:, line:, line_offset:, row:,
                                    width:)
              _plain_text, styled_text = @content_composer.compose(
                line,
                width,
                config_reader,
                line_offset: line_offset,
                hovered_inline_link: hovered_inline_link
              )
              abs_row, abs_col = absolute_cell(bounds, row, col)
              clipped_styled, clipped_plain = clip_to_bounds(styled_text, width, bounds, abs_col)
              PreparedLine.new(
                abs_row: abs_row,
                abs_col: abs_col,
                clipped_styled: clipped_styled,
                clipped_plain: clipped_plain
              )
            end

            def record_line_geometry(prepared_line, column_id:, line:, line_offset:, page_id:)
              return unless @record_geometry

              geometry = @geometry_builder.build(
                page_id: page_id,
                column_id: column_id,
                row: prepared_line.abs_row,
                col: prepared_line.abs_col,
                line_offset: line_offset,
                plain_text: prepared_line.clipped_plain,
                styled_text: prepared_line.clipped_styled
              )
              @recorder.record(geometry, line: line)
            end

            def clip_to_bounds(styled_text, width, bounds, abs_col)
              max_width = [width.to_i, bounds.right - abs_col + 1].min
              max_width = 0 if max_width.negative?
              start_column = [abs_col - 1, 0].max

              clipped_styled = clipped_styled_text(styled_text, max_width, start_column)
              clipped_plain = Shoko::Shared::Terminal::TextMetrics.strip_ansi(clipped_styled)
              [clipped_styled, clipped_plain]
            end

            def clipped_styled_text(styled_text, max_width, start_column)
              return '' unless max_width.positive?

              Shoko::Shared::Terminal::TextMetrics.truncate_to(
                styled_text.to_s,
                max_width,
                start_column: start_column
              )
            end
          end
        end
      end
    end
  end
end
