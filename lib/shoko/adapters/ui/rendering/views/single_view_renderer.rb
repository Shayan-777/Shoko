# frozen_string_literal: true

require_relative 'base_view_renderer'
require_relative '../../../../core/models/content_block'

module Shoko
  module Adapters
    module Ui
      module Components
        module Reading
          # Renderer for single-view reading mode (supports both dynamic and absolute page numbering)
          class SingleViewRenderer < BaseViewRenderer
            # Layout metrics for single-view rendering.
            SingleLayout = Struct.new(
              :col_width,
              :content_height,
              :spacing,
              :displayable,
              :col_start,
              keyword_init: true
            )

            # Encapsulates per-render state shared across helpers.
            RenderFrame = Struct.new(:surface, :bounds, :context, :layout, keyword_init: true)

            private_constant :SingleLayout, :RenderFrame

            def initialize(dependencies, page_numbering_mode: :dynamic)
              super(dependencies)
              @page_numbering_mode = page_numbering_mode
            end

            def render_with_context(surface, bounds, context)
              mode = context.page_numbering_mode || @page_numbering_mode
              if mode == :dynamic
                render_dynamic_mode_with_context(surface, bounds, context)
              else
                render_absolute_mode_with_context(surface, bounds, context)
              end
            end

            private

            # Context-based rendering methods
            def render_dynamic_mode_with_context(surface, bounds, context)
              layout = single_layout(bounds, context.config_reader)
              frame = RenderFrame.new(surface: surface, bounds: bounds, context: context, layout: layout)
              sidebar_visible = context.reader_state_reader&.sidebar_visible? == true

              page_data = context.page_calculator&.get_page(
                context.current_page_index,
                width: bounds.width,
                height: bounds.height,
                sidebar_visible: sidebar_visible
              )
              lines, line_offset = page_data ? dynamic_window(frame, page_data) : dynamic_fallback_window(frame)
              render_single_column(frame, lines, line_offset)
            end

            def render_absolute_mode_with_context(surface, bounds, context)
              chapter = context.current_chapter
              return unless chapter

              reader = context.reader_state_reader
              return unless reader

              layout = single_layout(bounds, context.config_reader)
              frame = RenderFrame.new(surface: surface, bounds: bounds, context: context, layout: layout)

              offset = reader.single_page
              chapter_index = reader.current_chapter
              lines, line_offset = fetch_window(
                frame,
                chapter_index: chapter_index,
                offset: offset,
                length: layout.displayable
              )
              render_single_column(frame, lines, line_offset)
            end

            def single_layout(bounds, config)
              col_width, content_height, spacing, displayable = compute_layout(bounds, :single, config)
              SingleLayout.new(
                col_width: col_width,
                content_height: content_height,
                spacing: spacing,
                displayable: displayable,
                col_start: center_start_col(bounds.width, col_width)
              )
            end

            def dynamic_window(frame, page_data)
              context = frame.context
              layout = frame.layout

              line_offset = page_data[:start_line].to_i
              end_line = page_data[:end_line].to_i
              span_length = [end_line - line_offset + 1, layout.displayable].max
              chapter_index = (page_data[:chapter_index] || context.reader_state_reader&.current_chapter || 0).to_i
              request = { chapter_index: chapter_index, offset: line_offset, length: span_length }

              lines = page_data[:lines] || []
              resolve_dynamic_lines(frame, lines, request)
            end

            def resolve_dynamic_lines(frame, lines, request)
              return fetch_window(frame, request) unless lines_fit_column?(lines, frame.layout.col_width)
              return fetch_window(frame, request) if lines.empty?

              line_offset = request.fetch(:offset)
              snapped = snap_offset_to_image_start(lines, line_offset)
              return [lines, line_offset] if snapped == line_offset

              fetch_window(frame, request.merge(offset: snapped))
            end

            def dynamic_fallback_window(frame)
              context = frame.context
              layout = frame.layout

              displayable = layout.displayable
              chapter_index = context&.reader_state_reader&.current_chapter || 0
              offset = compute_dynamic_offset(context, displayable)
              fetch_window(frame, chapter_index: chapter_index, offset: offset, length: displayable)
            end

            def fetch_window(frame, request)
              context = frame.context
              layout = frame.layout

              fetch_wrapped_lines_with_offset(
                document: context.document,
                chapter_index: request.fetch(:chapter_index),
                col_width: layout.col_width,
                offset: request.fetch(:offset),
                length: request.fetch(:length)
              )
            end

            def compute_dynamic_offset(context, displayable)
              pending = context.reader_state_reader&.pending_progress
              line_offset = pending && (pending[:line_offset] || pending['line_offset'])
              return line_offset.to_i if line_offset

              (context.current_page_index || 0) * [displayable, 1].max
            end

            def render_single_column(frame, lines, line_offset)
              layout = frame.layout
              context = frame.context

              start_row = calculate_center_start_row(layout.content_height, lines.size, layout.spacing)
              params = Adapters::Ui::Rendering::Models::RenderParams.new(start_row: start_row, col_start: layout.col_start,
                                                                         col_width: layout.col_width, context: context,
                                                                         line_offset: line_offset,
                                                                         page_id: context.current_page_index,
                                                                         column_id: 0)
              draw_lines(frame.surface, frame.bounds, lines, params)
            end

            def lines_fit_column?(lines, col_width)
              width = col_width.to_i
              return true if width <= 0

              Array(lines).first(6).all? do |line|
                next true unless line
                next true if image_line?(line)

                text = line.is_a?(Shoko::Core::Models::DisplayLine) ? line.text.to_s : line.to_s
                Shoko::Shared::Terminal::TextMetrics.visible_length(text) <= width
              end
            rescue Shoko::Error
              true
            end

            def image_line?(line)
              return false unless line.is_a?(Shoko::Core::Models::DisplayLine)

              meta = line.metadata
              return false unless meta.is_a?(Hash)

              block_type = meta[:block_type] || meta['block_type']
              block_type == :image || block_type.to_s == 'image'
            rescue Shoko::Error
              raise
            end

            # helpers provided by BaseViewRenderer
          end
        end
      end
    end
  end
end
