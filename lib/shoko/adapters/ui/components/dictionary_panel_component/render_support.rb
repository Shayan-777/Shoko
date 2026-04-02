# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        # Rendering helpers for the side dictionary panel.
        module DictionaryPanelRenderSupport
          PanelContentContext = Data.define(:surface, :bounds, :content_start_y, :content_height, :content_width)

          private

          def render_content(surface, bounds)
            return unless @result

            context = panel_content_context(surface, bounds)
            ensure_formatted_lines(context.content_width)
            @last_content_height = context.content_height
            clamp_scroll_offset(context.content_height)
            render_content_lines(context)
            render_scroll_indicators(surface, bounds, context.content_height)
          end

          def panel_content_context(surface, bounds)
            PanelContentContext.new(
              surface: surface,
              bounds: bounds,
              content_start_y: header_height + 1,
              content_height: bounds.height - header_height - footer_height,
              content_width: bounds.width - 4
            )
          end

          def ensure_formatted_lines(content_width)
            return unless @formatted_lines.empty?

            @formatter = Dictionary::EntryFormatter.new(width: content_width, color_mode: @color_mode)
            @formatted_lines = if @fuzzy_mode
                                 @formatter.format_fuzzy_results(@fuzzy_matches, @result.query)
                               else
                                 @formatter.format_result(@result, entry_index: @entry_index)
                               end
          end

          def clamp_scroll_offset(content_height)
            max_scroll = [@formatted_lines.length - content_height, 0].max
            @scroll_offset = [@scroll_offset, max_scroll].min
          end

          def render_content_lines(context)
            visible_lines = @formatted_lines[@scroll_offset, context.content_height] || []
            visible_lines.each_with_index do |line, index|
              row = context.content_start_y + index
              break if row > context.bounds.height - footer_height

              truncated = Ui::TextUtils.truncate_text(line.to_s, context.content_width)
              context.surface.write(context.bounds, row, 3, truncated)
            end
          end

          def header_height
            self.class::HEADER_HEIGHT
          end

          def footer_height
            self.class::FOOTER_HEIGHT
          end
        end
      end
    end
  end
end
