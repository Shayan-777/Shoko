# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module DictionaryPopup
          # Result-set behavior and rendering for dictionary popup.
          module ResultsFlow
            PanelContentContext = Data.define(:surface,
                                              :bounds,
                                              :content_x,
                                              :content_y,
                                              :content_width,
                                              :content_height)

            def advance_entry!
              return nil unless @result && @result.entry_count > 1
              return nil if @fuzzy_mode

              @entry_index = (@entry_index + 1) % @result.entry_count
              @formatted_lines = []
              @scroll_offset = 0
              :advanced
            end
            alias next_entry advance_entry!

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
              sync_from_state
              fill_panel_background(surface, bounds, layout)
              context = build_content_context(surface, bounds, layout)
              @last_content_height = context.content_height
              render_content(context)
              render_footer(surface, bounds, layout, context)
            end

            def render_content(context)
              return unless @result

              ensure_formatted_lines(context.content_width)
              render_visible_lines(context)
              fill_empty_lines(context)
              render_scroll_indicators(context)
            end

            def render_scroll_indicators(context)
              return unless @formatted_lines.length > context.content_height

              render_up_scroll_indicator(context) if @scroll_offset.positive?
              return unless more_content_below?(context)

              render_down_scroll_indicator(context)
            end

            def render_footer(surface, bounds, layout, context)
              footer_row = layout.origin_y + layout.height - 1

              dim = "\e[2m"
              nodim = "\e[22m"
              hints = "#{dim}Esc#{nodim} close  #{dim}Tab#{nodim} next  #{dim}f#{nodim} fuzzy"
              padded = pad_line(hints, context.content_width)
              surface.write(bounds, footer_row, context.content_x, padded)
            end

            private

            # Lookup result/entry/fuzzy are observable reader view-state; pull them
            # in for the results view and invalidate the format cache on change.
            # (Setup rendering is self-owned and does not call this.)
            def sync_from_state
              return unless @reader_state_reader.respond_to?(:dictionary_result)

              result = @reader_state_reader.dictionary_result
              entry_index = @reader_state_reader.dictionary_entry_index.to_i
              fuzzy_mode = @reader_state_reader.dictionary_fuzzy_mode == true
              fuzzy_matches = Array(@reader_state_reader.dictionary_fuzzy_matches)
              return if result == @result && entry_index == @entry_index &&
                        fuzzy_mode == @fuzzy_mode && fuzzy_matches == @fuzzy_matches

              @result = result
              @entry_index = entry_index
              @fuzzy_mode = fuzzy_mode
              @fuzzy_matches = fuzzy_matches
              @formatted_lines = []
              @scroll_offset = 0
            end

            def fill_panel_background(surface, bounds, layout)
              layout.height.times do |offset|
                surface.write(bounds,
                              layout.origin_y + offset,
                              layout.origin_x,
                              "#{panel_bg}#{' ' * layout.width}#{reset}")
              end
            end

            def build_content_context(surface, bounds, layout)
              padding_h = self.class::PADDING_H
              padding_v = self.class::PADDING_V
              PanelContentContext.new(
                surface: surface,
                bounds: bounds,
                content_x: layout.origin_x + padding_h,
                content_y: layout.origin_y + padding_v,
                content_width: layout.width - (padding_h * 2),
                content_height: layout.height - (padding_v * 2) - 1
              )
            end

            def ensure_formatted_lines(content_width)
              return unless @formatted_lines.empty?

              @formatter = Dictionary::EntryFormatter.new(width: content_width,
                                                          background: panel_bg,
                                                          color_mode: @color_mode)
              @formatted_lines = if @fuzzy_mode
                                   @formatter.format_fuzzy_results(@fuzzy_matches, @result.query)
                                 else
                                   @formatter.format_result(@result, entry_index: @entry_index)
                                 end
            end

            def indicator_x(context)
              context.content_x + context.content_width - 1
            end

            def render_up_scroll_indicator(context)
              context.surface.write(context.bounds, context.content_y, indicator_x(context), "#{panel_bg}\e[2m▲\e[22m")
            end

            def render_down_scroll_indicator(context)
              context.surface.write(
                context.bounds,
                context.content_y + context.content_height - 1,
                indicator_x(context),
                "#{panel_bg}\e[2m▼\e[22m"
              )
            end

            def more_content_below?(context)
              @scroll_offset < @formatted_lines.length - context.content_height
            end

            def render_visible_lines(context)
              visible_lines = @formatted_lines[@scroll_offset, context.content_height] || []
              visible_lines.each_with_index do |line, index|
                row = context.content_y + index
                context.surface.write(context.bounds,
                                      row,
                                      context.content_x,
                                      pad_line(line.to_s, context.content_width))
              end
            end

            def fill_empty_lines(context)
              visible_count = (@formatted_lines[@scroll_offset, context.content_height] || []).length
              empty_line = "#{panel_bg}#{' ' * context.content_width}#{reset}"
              remaining = context.content_height - visible_count
              remaining.times do |index|
                row = context.content_y + visible_count + index
                context.surface.write(context.bounds, row, context.content_x, empty_line)
              end
            end
          end
        end
      end
    end
  end
end
