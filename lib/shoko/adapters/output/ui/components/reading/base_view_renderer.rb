# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../../rendering/models/rendering_context'
require_relative '../../../rendering/models/render_params'
require_relative '../../../terminal/text_metrics'
require_relative 'config_helpers'
require_relative 'line_drawer'
require_relative 'wrapped_lines_fetcher'

module Shoko
  module Adapters::Output::Ui::Components
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

          @layout_service = @dependencies.resolve(:layout_service)
          @layout_metrics = resolve_layout_metrics
          @wrapped_lines_fetcher = WrappedLinesFetcher.new(@dependencies)
          @render_state_writer = resolve_render_state_writer
          @logger = resolve_logger
          @line_drawer = nil
          @last_render_key = nil
        end

        # Standard BaseComponent implementation
        def do_render(surface, bounds)
          context = create_rendering_context
          return unless context

          render_key = render_key_for(context, bounds)
          record_geometry = rendered_lines_missing?(context.state) || render_key != @last_render_key
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
            dispatch_rendered_lines(context.state, rendered_lines_buffer)
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
              "#{Shoko::Adapters::Output::Ui::Constants::UI::BORDER_PRIMARY}│#{Terminal::ANSI::RESET}"
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
          spacing = ctx ? ConfigHelpers.line_spacing(ctx.config) : :normal
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
          state = @dependencies.resolve(:global_state)
          Adapters::Output::Rendering::Models::RenderingContext.new(
            document: safe_resolve(:document),
            page_calculator: safe_resolve(:page_calculator),
            state: state,
            config: state,
            view_model: nil
          )
        end

        def safe_resolve(name)
          @dependencies.registered?(name) ? @dependencies.resolve(name) : nil
        end

        def dispatch_rendered_lines(_state, rendered_lines)
          @render_state_writer&.update_rendered_lines(rendered_lines)
        rescue StandardError => e
          @logger&.error('base_view_renderer.dispatch_rendered_lines_failed',
                         error: e.class.name,
                         message: e.message,
                         backtrace: e.backtrace&.first(3)&.join("\n"))
        end

        def render_key_for(context, bounds)
          state = context.state
          [
            bounds.width,
            bounds.height,
            state.get(%i[reader current_chapter]),
            state.get(%i[reader current_page_index]),
            state.get(%i[reader left_page]),
            state.get(%i[reader right_page]),
            state.get(%i[reader single_page]),
            context.view_mode,
            context.page_numbering_mode,
            Shoko::Application::Selectors::ConfigSelectors.line_spacing(state),
            Shoko::Application::Selectors::ConfigSelectors.kitty_images(state),
            context.document&.object_id,
          ]
        end

        def rendered_lines_missing?(state)
          lines = Shoko::Application::Selectors::ReaderSelectors.rendered_lines(state)
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

        def resolve_render_state_writer
          @dependencies.resolve(:render_state_writer)
        rescue StandardError
          nil
        end

        def resolve_logger
          @dependencies.resolve(:logger)
        rescue StandardError
          nil
        end

        def resolve_layout_metrics
          @dependencies.resolve(:layout_metrics)
        rescue StandardError
          nil
        end
      end
    end
  end
end
