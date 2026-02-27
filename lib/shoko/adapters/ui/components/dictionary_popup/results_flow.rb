# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module DictionaryPopup
          # Result-set behavior and rendering for dictionary popup.
          module ResultsFlow
            def next_entry
              return false unless @result && @result.entry_count > 1
              return false if @fuzzy_mode

              @entry_index = (@entry_index + 1) % @result.entry_count
              @formatted_lines = []
              @scroll_offset = 0
              true
            end

            def toggle_fuzzy(matches = nil)
              if @fuzzy_mode
                @fuzzy_mode = false
                @fuzzy_matches = []
              else
                @fuzzy_mode = true
                @fuzzy_matches = Array(matches)
              end
              @formatted_lines = []
              @scroll_offset = 0
            end

            def fuzzy_mode?
              @fuzzy_mode
            end

            def render_panel(surface, bounds, layout)
              bg = panel_bg

              # Fill entire panel with dark background
              layout.height.times do |offset|
                surface.write(bounds, layout.origin_y + offset, layout.origin_x,
                              "#{bg}#{' ' * layout.width}#{reset}")
              end

              # Content area dimensions
              padding_h = self.class::PADDING_H
              padding_v = self.class::PADDING_V
              content_x = layout.origin_x + padding_h
              content_width = layout.width - (padding_h * 2)
              content_y = layout.origin_y + padding_v
              content_height = layout.height - (padding_v * 2) - 1
              @last_content_height = content_height

              render_content(surface, bounds, content_x, content_y, content_width, content_height)
              render_footer(surface, bounds, layout, content_x, content_width)
            end

            def render_content(surface, bounds, content_x, content_y, content_width, content_height)
              return unless @result

              bg = panel_bg

              # Generate formatted lines if needed
              if @formatted_lines.empty?
                @formatter = Dictionary::EntryFormatter.new(width: content_width, background: bg, color_mode: @color_mode)
                @formatted_lines = if @fuzzy_mode
                                     @formatter.format_fuzzy_results(@fuzzy_matches, @result.query)
                                   else
                                     @formatter.format_result(@result, entry_index: @entry_index)
                                   end
              end

              # Visible slice
              visible_lines = @formatted_lines[@scroll_offset, content_height] || []

              visible_lines.each_with_index do |line, idx|
                row = content_y + idx
                padded = pad_line(line.to_s, content_width)
                surface.write(bounds, row, content_x, padded)
              end

              # Fill remaining empty lines
              remaining = content_height - visible_lines.length
              empty_line = "#{bg}#{' ' * content_width}#{reset}"
              remaining.times do |i|
                row = content_y + visible_lines.length + i
                surface.write(bounds, row, content_x, empty_line)
              end

              # Scroll indicators
              return unless @formatted_lines.length > content_height

              render_scroll_indicators(surface, bounds, content_x, content_y, content_width, content_height)
            end

            def render_scroll_indicators(surface, bounds, content_x, content_y, content_width, content_height)
              bg = panel_bg
              indicator_x = content_x + content_width - 1

              surface.write(bounds, content_y, indicator_x, "#{bg}\e[2m▲\e[22m") if @scroll_offset.positive?
              return unless @scroll_offset < @formatted_lines.length - content_height

              surface.write(bounds, content_y + content_height - 1, indicator_x, "#{bg}\e[2m▼\e[22m")
            end

            def render_footer(surface, bounds, layout, content_x, content_width)
              panel_bg
              footer_row = layout.origin_y + layout.height - 1

              # Subtle footer with key hints (using style resets that preserve bg)
              dim = "\e[2m"
              nodim = "\e[22m"
              hints = "#{dim}Esc#{nodim} close  #{dim}Tab#{nodim} next  #{dim}f#{nodim} fuzzy"
              padded = pad_line(hints, content_width)
              surface.write(bounds, footer_row, content_x, padded)
            end
          end
        end
      end
    end
  end
end
