# frozen_string_literal: true

module Shoko
  module Core
    module BookFormats
      module Rtf
        # Output assembly and formatting state helpers for RTF parser.
        module RtfParserOutputHelpers
          private

          def flush_text
            return if @current_text.empty?

            @current_runs << self.class::TextRun.new(
              text: @current_text,
              bold: @bold,
              italic: @italic,
              underline: @underline,
              strikethrough: @strikethrough,
              superscript: @superscript,
              subscript: @subscript,
              font_size: @font_size,
              font_index: @font_index,
              color_index: @color_index
            )
            @current_text = +''
          end

          def flush_paragraph
            flush_text
            return if drop_empty_paragraph?

            @had_content = true
            append_paragraph
            @current_runs = []
            @page_break_next = false
          end

          def drop_empty_paragraph?
            return true if @current_runs.empty?
            return false unless whitespace_only_paragraph?
            return false if @had_content

            @current_runs.clear
            true
          end

          def whitespace_only_paragraph?
            @current_runs.map(&:text).join.strip.empty?
          end

          def append_paragraph
            @paragraphs << self.class::Paragraph.new(
              runs: @current_runs,
              alignment: @alignment,
              first_indent: @first_indent,
              space_before: @space_before,
              space_after: @space_after,
              page_break_before: @page_break_next
            )
          end

          def reset_char_formatting
            @bold = false
            @italic = false
            @underline = false
            @strikethrough = false
            @superscript = false
            @subscript = false
            @font_size = 24
            @font_index = 0
            @color_index = 0
          end

          def reset_para_formatting
            @alignment = :left
            @first_indent = 0
            @space_before = 0
            @space_after = 0
          end

          def push_state
            @state_stack << [
              @bold,
              @italic,
              @underline,
              @strikethrough,
              @superscript,
              @subscript,
              @font_index,
              @font_size,
              @color_index,
              @uc_skip,
            ]
          end

          def pop_state
            return if @state_stack.empty?

            @bold,
              @italic,
              @underline,
              @strikethrough,
              @superscript,
              @subscript,
              @font_index,
              @font_size,
              @color_index,
              @uc_skip = @state_stack.pop
          end

          def finish_font_entry
            return unless @current_font_id

            name = @current_font_name.strip.chomp(';').strip
            @fonts[@current_font_id] = name unless name.empty?
          end

          def parse_color_entry
            text = @colortbl_text
            @colortbl_text = +''
            @colors << [
              color_component(text, 'red'),
              color_component(text, 'green'),
              color_component(text, 'blue'),
            ]
          end

          def color_component(text, channel)
            match = text.match(/#{channel}(\d+)/)
            match ? match[1].to_i : 0
          end

          def finish_colortbl
            return if @colortbl_text.strip.empty?

            parse_color_entry
          end

          def finish_info_field
            case @info_field
            when 'title'
              @info.title = @info_text.strip
            when 'author'
              @info.author = @info_text.strip
            when 'operator'
              @info.operator = @info_text.strip
            when 'company'
              @info.company = @info_text.strip
            when 'creatim'
              @info.creatim = format_date(@info_date_parts)
            when 'revtim'
              @info.revtim = format_date(@info_date_parts)
            end
          end

          def format_date(parts)
            return nil if parts.empty?

            year = parts['yr']
            month = parts['mo']
            day = parts['dy']
            return nil unless year

            "#{year}-#{month.to_s.rjust(2, '0')}-#{day.to_s.rjust(2, '0')}"
          end
        end
      end
    end
  end
end
