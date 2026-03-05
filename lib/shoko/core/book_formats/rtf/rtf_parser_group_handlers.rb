# frozen_string_literal: true

module Shoko
  module Core
    module BookFormats
      module Rtf
        # Group open/close handling for RTF parser state transitions.
        module RtfParserGroupHandlers
          private

          def handle_group_open
            @pos += 1
            push_state
            track_nested_group_open
            increment_skip_depth_if_needed
          end

          def handle_group_close
            @pos += 1
            closing = decrement_group_depths
            return close_skipped_group if @skip_depth.positive?
            return close_font_table_group if closing[:fonttbl]
            return close_color_table_group if @in_colortbl
            return close_info_group if closing[:info]

            flush_text
            pop_state
          end

          def track_nested_group_open
            increment_font_table_depth
            @info_depth += 1 if @in_info
          end

          def increment_font_table_depth
            return unless @in_fonttbl

            @fonttbl_depth += 1
            return unless @fonttbl_depth == 1 && @skip_depth.zero?

            @current_font_id = nil
            @current_font_name = +''
          end

          def increment_skip_depth_if_needed
            return unless @skip_depth.positive?

            @skip_depth += 1
          end

          def decrement_group_depths
            {
              fonttbl: decrement_font_table_depth?,
              info: decrement_info_depth?,
            }
          end

          def decrement_font_table_depth?
            return false unless @in_fonttbl

            @fonttbl_depth -= 1
            true
          end

          def decrement_info_depth?
            return false unless @in_info

            @info_depth -= 1
            true
          end

          def close_skipped_group
            @skip_depth -= 1
            pop_state
          end

          def close_font_table_group
            if @fonttbl_depth.zero?
              finish_font_entry
              pop_state
              return
            end

            if @fonttbl_depth.negative?
              @in_fonttbl = false
              @fonttbl_depth = 0
            end
            pop_state
          end

          def close_color_table_group
            finish_colortbl
            @in_colortbl = false
            pop_state
          end

          def close_info_group
            if @info_depth.negative?
              @in_info = false
              @info_depth = 0
              pop_state
              return
            end

            finish_active_info_field
            pop_state
          end

          def finish_active_info_field
            return unless @info_field

            finish_info_field
            @info_field = nil
            @info_text = +''
            @info_date_parts = {}
          end
        end
      end
    end
  end
end
