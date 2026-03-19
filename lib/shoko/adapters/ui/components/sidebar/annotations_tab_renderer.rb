# frozen_string_literal: true

require_relative '../base_component'
require_relative '../ui/list_helpers'
require_relative '../ui/text_utils'

module Shoko
  module Adapters
    module Ui
      module Components
        module Sidebar
          # Annotations tab renderer for sidebar
          class AnnotationsTabRenderer < BaseComponent
            include Adapters::Ui::Constants::Ui

            ItemCtx = Struct.new(:annotation, :index, :selected_index, :y)

            def initialize(dependencies: nil)
              super()
              @dependencies = dependencies
              @reader_state_reader = nil
            end

            BoundsMetrics = Struct.new(:x, :y, :width, :height)

            def do_render(surface, bounds)
              metrics = metrics_for(bounds)
              annotations = reader_state_reader&.annotations || []
              selected_index = reader_state_reader&.sidebar_annotations_selected || 0

              return render_empty_message(surface, bounds, metrics) if annotations.empty?

              render_annotations_list(
                surface,
                bounds,
                metrics: metrics,
                annotations: annotations,
                selected_index: selected_index
              )
            end

            def reader_state_reader
              return @reader_state_reader if @reader_state_reader

              @reader_state_reader = @dependencies&.reader_state_reader
            end

            private

            def metrics_for(bounds)
              BoundsMetrics.new(x: 1, y: 1, width: bounds.width, height: bounds.height)
            end

            def render_empty_message(surface, bounds, metrics)
              render_centered_messages(
                surface,
                bounds,
                metrics,
                ['No annotations yet', '', 'Select text while reading', 'to create annotations']
              )
            end

            def render_annotations_list(surface, bounds, metrics:, annotations:, selected_index:)
              item_height = 3
              current_y = metrics.y
              visible_annotations(annotations, metrics, selected_index).each do |row|
                break if current_y + item_height > metrics.y + metrics.height

                ctx = ItemCtx.new(
                  annotation: row[:annotation],
                  index: row[:index],
                  selected_index: selected_index,
                  y: current_y
                )
                render_annotation_item(surface, bounds, metrics, ctx)
                current_y += item_height
              end
            end

            def render_annotation_item(surface, bounds, metrics, ctx)
              row = ctx.y
              col = metrics.x + 1
              max_width = metrics.width - 4
              surface.write(bounds, row, col, annotation_excerpt_line(ctx, max_width))
              write_annotation_note_line(surface, bounds, ctx, row: row + 1, col: col, max_width: max_width)
              surface.write(bounds, row + 2, col, annotation_location_line(ctx, max_width))
            end

            def get_color_indicator(color)
              reset = Shoko::Shared::Terminal::Ansi::RESET
              case color&.downcase
              when 'yellow', 'highlight'
                "#{COLOR_TEXT_WARNING}●#{reset} "
              when 'red'
                "#{COLOR_TEXT_ERROR}●#{reset} "
              when 'green'
                "#{COLOR_TEXT_SUCCESS}●#{reset} "
              when 'blue'
                "#{COLOR_TEXT_ACCENT}●#{reset} "
              else
                "#{COLOR_TEXT_PRIMARY}●#{reset} "
              end
            end

            def format_location(annotation)
              ch_idx = annotation['chapter_index'] || 0
              chapter_title = annotation['chapter_title'] || "Ch. #{ch_idx + 1}"

              # Try to calculate percentage if we have position info
              percentage = ''
              start_pos = annotation['start_position']
              ch_len = annotation['chapter_length']
              if start_pos && ch_len
                pct = (start_pos.to_f / ch_len * 100).round
                percentage = " · #{pct}%"
              end

              "#{chapter_title}#{percentage}"
            end

            def render_centered_messages(surface, bounds, metrics, messages)
              reset = Shoko::Shared::Terminal::Ansi::RESET
              start_y = ((metrics.height - messages.length) / 2) + 1
              messages.each_with_index do |message, index|
                msg_width = Shoko::Shared::Terminal::TextMetrics.visible_length(message)
                col = [(metrics.width - msg_width) / 2, 2].max
                row = start_y + index
                surface.write(bounds, row, col, "#{COLOR_TEXT_DIM}#{message}#{reset}")
              end
            end

            def visible_annotations(annotations, metrics, selected_index)
              visible_items = [metrics.height / 3, 1].max
              start_index, visible = Ui::ListHelpers.slice_visible(annotations, visible_items, selected_index)
              visible.each_with_index.map do |annotation, offset|
                { annotation: annotation, index: start_index + offset }
              end
            end

            def annotation_excerpt_line(ctx, max_width)
              styles = annotation_selection_style(ctx.index == ctx.selected_index)
              excerpt = annotation_excerpt(ctx.annotation, max_width)
              "#{styles[:prefix]}#{get_color_indicator(ctx.annotation['color'])}#{excerpt}#{styles[:reset]}"
            end

            def write_annotation_note_line(surface, bounds, ctx, row:, col:, max_width:)
              note_text = annotation_note(ctx.annotation, max_width)
              return if note_text.nil?

              styles = annotation_selection_style(ctx.index == ctx.selected_index)
              line = "  #{Shoko::Shared::Terminal::Ansi::ITALIC}#{styles[:note]}✎ #{note_text}#{styles[:reset]}"
              surface.write(bounds, row, col, line)
            end

            def annotation_location_line(ctx, max_width)
              styles = annotation_selection_style(ctx.index == ctx.selected_index)
              location = Ui::TextUtils.truncate_text(format_location(ctx.annotation), [max_width, 1].max)
              "  #{styles[:location]}#{location}#{styles[:reset]}"
            end

            def annotation_selection_style(selected)
              reset = Shoko::Shared::Terminal::Ansi::RESET
              return selected_annotation_style(reset) if selected

              unselected_annotation_style(reset)
            end

            def selected_annotation_style(reset)
              {
                prefix: "#{COLOR_TEXT_ACCENT}#{SELECTION_POINTER}#{reset}",
                note: COLOR_TEXT_PRIMARY,
                location: COLOR_TEXT_SECONDARY,
                reset: reset,
              }
            end

            def unselected_annotation_style(reset)
              {
                prefix: '  ',
                note: COLOR_TEXT_DIM,
                location: COLOR_TEXT_DIM,
                reset: reset,
              }
            end

            def annotation_excerpt(annotation, max_width)
              text = annotation['text'].to_s.tr("\n", ' ').strip
              Ui::TextUtils.truncate_text(text, [max_width - 6, 1].max)
            end

            def annotation_note(annotation, max_width)
              note = annotation['note'].to_s.strip
              return nil if note.empty?

              Ui::TextUtils.truncate_text(note.tr("\n", ' ').strip, [max_width - 5, 1].max)
            end
          end
        end
      end
    end
  end
end
