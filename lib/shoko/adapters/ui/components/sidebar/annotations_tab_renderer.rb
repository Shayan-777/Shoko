# frozen_string_literal: true

require_relative '../base_component'
require_relative '../ui/list_helpers'
require_relative '../ui/text_utils'

module Shoko
  module Adapters::Ui::Components
    module Sidebar
      # Annotations tab renderer for sidebar
      class AnnotationsTabRenderer < BaseComponent
        include Adapters::Ui::Constants::Ui

        ItemCtx = Struct.new(:annotation, :index, :selected_index, :y, keyword_init: true)

        def initialize(dependencies: nil)
          super()
          @dependencies = dependencies
          @reader_state_reader = nil
        end

        BoundsMetrics = Struct.new(:x, :y, :width, :height, keyword_init: true)

        def do_render(surface, bounds)
          metrics = metrics_for(bounds)
          annotations = reader_state_reader&.annotations || []
          selected_index = reader_state_reader&.sidebar_annotations_selected || 0

          return render_empty_message(surface, bounds, metrics) if annotations.empty?

          render_annotations_list(surface, bounds, metrics, annotations, selected_index)
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
          reset = Terminal::ANSI::RESET
          bw = metrics.width
          bh = metrics.height
          messages = [
            'No annotations yet',
            '',
            'Select text while reading',
            'to create annotations',
          ]

          start_y = ((bh - messages.length) / 2) + 1
          messages.each_with_index do |message, i|
            msg_width = Shoko::Shared::Terminal::TextMetrics.visible_length(message)
            x = [(bw - msg_width) / 2, 2].max
            y = start_y + i
            surface.write(bounds, y, x, "#{COLOR_TEXT_DIM}#{message}#{reset}")
          end
        end

        def render_annotations_list(surface, bounds, metrics, annotations, selected_index)
          # Each annotation takes 3 lines: text excerpt, note (if any), location
          item_height = 3
          bh = metrics.height
          by = metrics.y
          visible_items = [bh / item_height, 1].max
          window_start, window_items = Ui::ListHelpers.slice_visible(annotations, visible_items, selected_index)
          current_y = by

          window_items.each_with_index do |annotation, offset|
            idx = window_start + offset
            break if current_y + item_height > by + bh

            ctx = ItemCtx.new(annotation: annotation, index: idx, selected_index: selected_index, y: current_y)
            render_annotation_item(surface, bounds, metrics, ctx)
            current_y += item_height
          end
        end

        def render_annotation_item(surface, bounds, metrics, ctx)
          is_selected = (ctx.index == ctx.selected_index)
          bx = metrics.x
          bw = metrics.width
          max_width = bw - 4

          # Color indicator based on highlight color
          ann = ctx.annotation
          color_indicator = get_color_indicator(ann['color'])

          # Text excerpt (first line)
          text = ann['text'] || ''
          excerpt = text.tr("\n", ' ').strip
          excerpt = Ui::TextUtils.truncate_text(excerpt, [max_width - 6, 1].max)

          reset = Terminal::ANSI::RESET
          if is_selected
            prefix = "#{COLOR_TEXT_ACCENT}#{SELECTION_POINTER}#{reset}"
            note_style = COLOR_TEXT_PRIMARY
            location_style = COLOR_TEXT_SECONDARY
          else
            prefix = '  '
            note_style = COLOR_TEXT_DIM
            location_style = COLOR_TEXT_DIM
          end
          text_line = "#{prefix}#{color_indicator}#{excerpt}#{reset}"
          row = ctx.y
          col1 = bx + 1
          surface.write(bounds, row, col1, text_line)

          # Note (second line, if exists)
          note = ann['note']
          if note && !note.strip.empty?
            note_text = note.tr("\n", ' ').strip
            note_text = Ui::TextUtils.truncate_text(note_text, [max_width - 5, 1].max)

            note_line = "  #{Terminal::ANSI::ITALIC}#{note_style}✎ #{note_text}#{reset}"
            surface.write(bounds, row + 1, col1, note_line)
          end

          # Location (third line)
          location = format_location(ann)
          location = Ui::TextUtils.truncate_text(location, [max_width, 1].max)
          location_line = "  #{location_style}#{location}#{reset}"
          surface.write(bounds, row + 2, col1, location_line)
        end

        def get_color_indicator(color)
          reset = Terminal::ANSI::RESET
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
      end
    end
  end
end
