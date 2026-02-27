# frozen_string_literal: true

require_relative '../../components/base_component'
require_relative '../models/rendering_context'
require_relative '../models/render_params'
require_relative '../../../../shared/terminal/text_metrics'
require_relative '../line/render_dependencies'
require_relative '../line/config_helpers'
require_relative '../line/line_drawer'
require_relative '../line/wrapped_lines_fetcher'

module Shoko
  module Adapters
    module Ui
      module Components
        module Reading
          # Base class for all view renderers.
          #
          # Subclasses implement `render_with_context` and can use helpers for layout,
          # wrapped line fetching, and line drawing.
          class BaseViewRenderer < BaseComponent
            def initialize(dependencies)
              super()
              @dependencies = dependencies
              raise ArgumentError, 'Dependencies must be provided to BaseViewRenderer' unless @dependencies

              @layout_service = @dependencies.layout_service
              @layout_metrics = @dependencies.layout_metrics
              @wrapped_lines_fetcher = WrappedLinesFetcher.new(@dependencies)
              @render_state_writer = @dependencies.render_state_writer
              @config_reader = @dependencies.config_reader
              @reader_state_reader = @dependencies.reader_state_reader
              @rendered_content_reader = @dependencies.rendered_content_reader
              @logger = @dependencies.logger
              @line_drawer = nil
              @last_render_key = nil
            end

            # Standard BaseComponent implementation
            def do_render(surface, bounds)
              context = create_rendering_context
              return unless context

              render_key = render_key_for(context, bounds)
              record_geometry = rendered_lines_missing? || render_key != @last_render_key
              rendered_lines_buffer = record_geometry ? {} : nil
              placed_kitty_images = {}
              @line_drawer = LineDrawer.new(
                dependencies: @dependencies,
                rendered_lines_buffer: rendered_lines_buffer,
                placed_kitty_images: placed_kitty_images,
                record_geometry: record_geometry
              )

              render_with_context(surface, bounds, context)

              if record_geometry
                dispatch_rendered_lines(rendered_lines_buffer)
                @last_render_key = render_key
              end
            ensure
              @line_drawer = nil
            end

            # New rendering interface using context
            def render_with_context(surface, bounds, context)
              raise NotImplementedError, 'Subclasses must implement render_with_context method'
            end

            protected

            def layout_metrics(width, height, view_mode)
              @layout_service.calculate_metrics(width, height, view_mode)
            end

            def adjust_for_line_spacing(height, line_spacing = :normal)
              @layout_service.adjust_for_line_spacing(height, line_spacing)
            end

            def calculate_center_start_row(content_height, lines_count, line_spacing)
              @layout_service.calculate_center_start_row(content_height, lines_count, line_spacing)
            end

            # Compute common layout values for a given view mode.
            # Returns `[col_width, content_height, spacing, displayable]`.
            def compute_layout(bounds, view_mode, config)
              col_width, content_height = layout_metrics(bounds.width, bounds.height, view_mode)
              spacing = ConfigHelpers.line_spacing(config)
              displayable = adjust_for_line_spacing(content_height, spacing)
              [col_width, content_height, spacing, displayable]
            end

            # Draw a vertical divider between columns (shared helper)
            def draw_divider(surface, bounds, divider_col, start_row = 3)
              col = divider_col.to_i
              return if col <= 0

              (start_row..[bounds.height - 1, start_row + 1].max).each do |row|
                surface.write(
                  bounds,
                  row,
                  col,
                  "#{Shoko::Adapters::Ui::Constants::Ui::BORDER_PRIMARY}│#{Shoko::Shared::Terminal::Ansi::RESET}"
                )
              end
            end

            # Shared helpers for common renderer patterns
            def center_start_col(total_width, col_width)
              [(total_width - col_width) / 2, 1].max
            end

            def fetch_wrapped_lines(document:, chapter_index:, col_width:, offset:, length:)
              @wrapped_lines_fetcher.fetch(
                document: document,
                chapter_index: chapter_index,
                col_width: col_width,
                offset: offset,
                length: length
              )
            end

            def fetch_wrapped_lines_with_offset(document:, chapter_index:, col_width:, offset:, length:)
              @wrapped_lines_fetcher.fetch_with_offset(
                document: document,
                chapter_index: chapter_index,
                col_width: col_width,
                offset: offset,
                length: length
              )
            end

            def snap_offset_to_image_start(lines, offset)
              @wrapped_lines_fetcher.snap_offset_to_image_start(lines, offset)
            end

            # Shared helper to draw a list of lines with spacing and clipping considerations.
            def draw_lines(surface, bounds, lines, params)
              drawer = line_drawer
              ctx = params.context
              spacing = ctx ? ConfigHelpers.line_spacing(ctx.config_reader) : :normal
              lines.each_with_index do |line, idx|
                row = params.start_row + (spacing == :relaxed ? idx * 2 : idx)
                break if row > bounds.height - 1

                drawer.draw_line(surface: surface, bounds: bounds, line: line, row: row, col: params.col_start,
                                 width: params.col_width, context: ctx, column_id: params.column_id,
                                 line_offset: params.line_offset + idx, page_id: params.page_id)
              end
            end

            private

            def create_rendering_context
              Adapters::Ui::Rendering::Models::RenderingContext.new(
                document: resolve_document,
                page_calculator: @dependencies.page_calculator,
                config_reader: @config_reader,
                reader_state_reader: @reader_state_reader
              )
            end

            def resolve_document
              session_context = @dependencies.reader_session_context
              session_context&.document
            rescue StandardError
              nil
            end

            def dispatch_rendered_lines(rendered_lines)
              @render_state_writer&.update_rendered_lines(rendered_lines)
            rescue StandardError => e
              @logger&.error('base_view_renderer.dispatch_rendered_lines_failed',
                             error: e.class.name,
                             message: e.message,
                             backtrace: e.backtrace&.first(3)&.join("\n"))
            end

            def render_key_for(context, bounds)
              reader = context.reader_state_reader || @reader_state_reader
              config = context.config_reader || @config_reader
              [
                bounds.width,
                bounds.height,
                reader&.current_chapter,
                reader&.current_page_index,
                reader&.left_page,
                reader&.right_page,
                reader&.single_page,
                context.view_mode,
                context.page_numbering_mode,
                config&.line_spacing,
                config&.kitty_images,
                context.document&.object_id,
              ]
            end

            def rendered_lines_missing?
              lines = @rendered_content_reader&.rendered_lines
              !lines || lines.empty?
            rescue StandardError => e
              @logger&.warn('base_view_renderer.rendered_lines_missing_check_failed',
                            error: e.class.name,
                            message: e.message)
              true
            end

            def line_drawer
              return @line_drawer if @line_drawer

              raise ArgumentError, 'LineDrawer not initialized (do_render not active)'
            end
          end
        end
      end
    end
  end
end
