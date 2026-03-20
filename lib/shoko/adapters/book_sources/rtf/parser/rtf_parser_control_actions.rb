# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Rtf
        # Control-word formatting actions for RTF parser.
        module RtfParserControlActions
          CHARACTER_CONTROL_PAIRS = [
            ['b', :apply_bold_control],
            ['i', :apply_italic_control],
            ['ul', :apply_underline_control],
            ['uld', :apply_underline_control],
            ['uldb', :apply_underline_control],
            ['ulth', :apply_underline_control],
            ['ulw', :apply_underline_control],
            ['ulwave', :apply_underline_control],
            ['ulnone', :clear_underline_control],
            ['strike', :apply_strike_control],
            ['super', :apply_superscript_control],
            ['sub', :apply_subscript_control],
            ['nosupersub', :clear_script_control],
            ['fs', :apply_font_size_control],
            ['f', :apply_font_index_control],
            ['cf', :apply_color_index_control],
            ['plain', :apply_plain_control],
          ].freeze

          PARAGRAPH_CONTROL_PAIRS = [
            ['pard', :apply_paragraph_defaults],
            ['qc', :apply_center_alignment],
            ['qj', :apply_justify_alignment],
            ['ql', :apply_left_alignment],
            ['qr', :apply_right_alignment],
            ['fi', :apply_first_indent_control],
            ['sb', :apply_space_before_control],
            ['sa', :apply_space_after_control],
          ].freeze

          BREAK_CONTROL_PAIRS = [
            ['par', :apply_paragraph_break],
            ['page', :apply_page_break],
            ['pagebb', :apply_page_break],
            ['line', :apply_line_break],
            ['tab', :apply_tab_character],
          ].freeze

          private

          def dispatch_character_control?(word, param)
            handler = character_control_handlers[word]
            return false unless handler

            handler.call(param)
            true
          end

          def dispatch_paragraph_control?(word, param)
            handler = paragraph_control_handlers[word]
            return false unless handler

            handler.call(param)
            true
          end

          def dispatch_break_control?(word)
            handler = break_control_handlers[word]
            return false unless handler

            handler.call
            true
          end

          def character_control_handlers
            @character_control_handlers ||= callable_handler_map(CHARACTER_CONTROL_PAIRS)
          end

          def paragraph_control_handlers
            @paragraph_control_handlers ||= callable_handler_map(PARAGRAPH_CONTROL_PAIRS)
          end

          def break_control_handlers
            @break_control_handlers ||= callable_handler_map(BREAK_CONTROL_PAIRS)
          end

          def callable_handler_map(pairs)
            pairs.transform_values do |method_name|
              method(method_name)
            end
          end

          def dispatch_unicode_control(word, param)
            return handle_unicode(param) if word == 'u'

            @uc_skip = param || 1 if word == 'uc'
          end

          def apply_bold_control(param)
            flush_text
            @bold = param != 0
          end

          def apply_italic_control(param)
            flush_text
            @italic = param != 0
          end

          def apply_underline_control(param)
            flush_text
            @underline = param != 0
          end

          def clear_underline_control(_param)
            flush_text
            @underline = false
          end

          def apply_strike_control(param)
            flush_text
            @strikethrough = param != 0
          end

          def apply_superscript_control(_param)
            flush_text
            @superscript = true
            @subscript = false
          end

          def apply_subscript_control(_param)
            flush_text
            @subscript = true
            @superscript = false
          end

          def clear_script_control(_param)
            flush_text
            @superscript = false
            @subscript = false
          end

          def apply_font_size_control(param)
            flush_text
            @font_size = param || 24
          end

          def apply_font_index_control(param)
            flush_text
            @font_index = param || 0
          end

          def apply_color_index_control(param)
            flush_text
            @color_index = param || 0
          end

          def apply_plain_control(_param)
            flush_text
            reset_char_formatting
          end

          def apply_paragraph_defaults(_param)
            flush_text
            reset_para_formatting
          end

          def apply_center_alignment(_param)
            @alignment = :center
          end

          def apply_justify_alignment(_param)
            @alignment = :justify
          end

          def apply_left_alignment(_param)
            @alignment = :left
          end

          def apply_right_alignment(_param)
            @alignment = :right
          end

          def apply_first_indent_control(param)
            @first_indent = param || 0
          end

          def apply_space_before_control(param)
            @space_before = param || 0
          end

          def apply_space_after_control(param)
            @space_after = param || 0
          end

          def apply_paragraph_break
            flush_paragraph
          end

          def apply_page_break
            flush_paragraph
            @page_break_next = true
          end

          def apply_line_break
            append_char("\n")
          end

          def apply_tab_character
            append_char("\t")
          end
        end
      end
    end
  end
end
