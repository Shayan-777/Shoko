# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Sidebar
          # Calculates components of an entry (prefix, icon, title).
          class EntryComponents
            attr_reader :prefix, :icon, :title, :entry, :continuation_prefix

            def initialize(item_entries, entry, index, full_entries:, full_index:, collapsed_set:, filter_active:,
                           text_metrics:)
              @entry = entry
              @text_metrics = text_metrics
              @prefix = TreeFormatter.prefix(item_entries, index, entry.level)
              @icon = IconSelector.select(
                full_entries,
                entry,
                full_index,
                collapsed_set: collapsed_set,
                filter_active: filter_active
              )
              @title = EntryTitleFormatter.format(entry)
              @continuation_prefix = IndentCalculator.new(
                item_entries,
                index,
                entry.level,
                icon_present: icon_present?
              ).build
            end

            def icon_present?
              !@icon.empty?
            end

            def width_without_title
              prefix_width + icon_width + spacer_width
            end

            private

            def spacer_width
              icon_present? ? 1 : 0
            end

            def prefix_width
              @text_metrics.visible_length(@prefix)
            end

            def icon_width
              @text_metrics.visible_length(@icon)
            end
          end

          # Renders a single TOC entry.
          class EntryRenderer
            include Adapters::Ui::Constants::Ui

            def initialize(context, item)
              @context = context
              @item = item
            end

            def render
              render_lines
            end

            private

            def render_lines
              formatter = EntryFormatter.new(@item)
              lines = formatter.lines
              start = @item.start_offset
              visible = @item.visible_height
              lines_to_render = lines.slice(start, visible) || []

              lines_to_render.each_with_index do |line, offset|
                y_pos = @item.screen_y + offset
                write_gutter(y_pos)
                write_content(y_pos, line)
              end
            end

            def write_gutter(y_pos)
              gutter = gutter_symbol + Shoko::Shared::Terminal::Ansi::RESET
              @context.write(y_pos, @context.metrics.x, gutter)
            end

            def gutter_symbol
              @item.selected? ? "#{COLOR_TEXT_ACCENT}│" : "#{COLOR_TEXT_DIM}│"
            end

            def write_content(y_pos, line)
              @context.write(y_pos, @context.metrics.x + 2, line)
            end
          end

          # Formats entry text with tree structure.
          class EntryFormatter
            include Adapters::Ui::Constants::Ui

            def initialize(item)
              @item = item
              @components = item.components
            end

            def lines
              builder = EntryLineBuilder.new(@components, @item.wrapped_lines)
              @item.selected? ? builder.build_selected : builder.build
            end
          end

          # Builds multi-line entry strings.
          class EntryLineBuilder
            include Adapters::Ui::Constants::Ui

            def initialize(components, wrapped_lines)
              @components = components
              @entry = components.entry
              @wrapped_lines = wrapped_lines
            end

            def build
              build_lines { |line, idx| format_line(line, idx) }
            end

            def build_selected
              build_lines { |line, idx| format_selected_line(line, idx) }
            end

            private

            def build_lines(&)
              @wrapped_lines.map.with_index(&)
            end

            def format_line(line, idx)
              idx.zero? ? format_first_line(line) : format_continuation_line(line)
            end

            def format_selected_line(line, idx)
              plain = idx.zero? ? plain_first_line(line) : plain_continuation_line(line)
              "#{Shoko::Shared::Terminal::Ansi::BG_GREY}#{Shoko::Shared::Terminal::Ansi::WHITE}#{plain}#{Shoko::Shared::Terminal::Ansi::RESET}"
            end

            def format_first_line(line)
              parts = []
              prefix = @components.prefix
              parts << colorize(prefix, COLOR_TEXT_DIM) unless prefix.empty?

              if @components.icon_present?
                parts << colorize(@components.icon, EntryStyler.icon_color(@entry))
                parts << ' '
              end

              parts << colorize(line, EntryStyler.title_color(@entry))
              parts.join
            end

            def format_continuation_line(line)
              prefix = @components.continuation_prefix
              styled_prefix = prefix.empty? ? '' : colorize(prefix, COLOR_TEXT_DIM)
              "#{styled_prefix}#{colorize(line, EntryStyler.title_color(@entry))}"
            end

            def plain_first_line(line)
              spacer = @components.icon_present? ? ' ' : ''
              "#{@components.prefix}#{@components.icon}#{spacer}#{line}"
            end

            def plain_continuation_line(line)
              "#{@components.continuation_prefix}#{line}"
            end

            def colorize(text, color)
              return text if text.empty? || color.nil?

              "#{color}#{text}#{Shoko::Shared::Terminal::Ansi::RESET}"
            end
          end
        end
      end
    end
  end
end
