# frozen_string_literal: true



module Shoko
  module Adapters
    module BookSources
      module Rtf
        # Single-pass RTF tokenizer and document model builder.
        #
        # Parses an RTF string into a structured DocumentModel containing
        # paragraphs with styled text runs, plus font/color tables and
        # document metadata from the \info group.
        class RtfParser
          Paragraph = Struct.new(:runs, :alignment, :first_indent, :space_before, :space_after, :page_break_before)
          TextRun = Struct.new(:text,
                               :bold,
                               :italic,
                               :underline,
                               :strikethrough,
                               :superscript,
                               :subscript,
                               :font_size,
                               :font_index,
                               :color_index)
          DocumentModel = Struct.new(:paragraphs, :fonts, :colors, :info)
          InfoFields = Struct.new(:title, :author, :operator, :company, :creatim, :revtim)

          NAMED_CHARS = {
            'emdash' => "\u2014",
            'endash' => "\u2013",
            'lquote' => "\u2018",
            'rquote' => "\u2019",
            'ldblquote' => "\u201C",
            'rdblquote' => "\u201D",
            'bullet' => "\u2022",
            'emspace' => "\u2003",
            'enspace' => "\u2002",
            'qmspace' => "\u2005",
            'zwj' => "\u200D",
            'zwnj' => "\u200C",
          }.freeze

          SKIP_DESTINATIONS = Set.new(
            %w[
              stylesheet listtable listoverridetable revtbl rsidtbl
              generator pnseclvl latentstyles colorschememapping
              themedata datastore mailmerge pgptbl xmlnstbl
              header footer headerl headerr headerf
              footerl footerr footerf
              pict object datafield fldinst mmathPr
            ]
          ).freeze

          INFO_DESTINATIONS = Set.new(%w[title author operator company]).freeze
          BRACE_BYTES = [123, 125].freeze

          # @param rtf_string [String] raw RTF content
          # @param codepage [Integer] default codepage (overridden by \ansicpg)
          def initialize(rtf_string, codepage: 1252)
            @rtf = rtf_string.to_s
            @codepage = codepage
            @pos = 0
            @len = @rtf.length

            initialize_parser_state
          end

          # Parse the RTF string and return a DocumentModel.
          # @return [DocumentModel]
          def parse
            detect_codepage
            scan
            flush_paragraph
            DocumentModel.new(paragraphs: @paragraphs, fonts: @fonts, colors: @colors, info: @info)
          end


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


          INFO_DATE_PARTS = Set.new(%w[yr mo dy hr min sec]).freeze


          private

          def initialize_parser_state
            initialize_character_state
            initialize_destination_state
            initialize_table_state
            initialize_info_state
            initialize_output_state
          end

          def initialize_character_state
            @state_stack = []
            @bold = false
            @italic = false
            @underline = false
            @strikethrough = false
            @superscript = false
            @subscript = false
            @font_index = 0
            @font_size = 24
            @color_index = 0
            @alignment = :left
            @first_indent = 0
            @space_before = 0
            @space_after = 0
            @uc_skip = 1
          end

          def initialize_destination_state
            @skip_depth = 0
            @ignorable_next = false
          end

          def initialize_table_state
            @in_fonttbl = false
            @fonttbl_depth = 0
            @current_font_id = nil
            @current_font_name = +''
            @in_colortbl = false
            @colortbl_text = +''
          end

          def initialize_info_state
            @in_info = false
            @info_depth = 0
            @info_field = nil
            @info_text = +''
            @info_date_parts = {}
          end

          def initialize_output_state
            @paragraphs = []
            @current_runs = []
            @current_text = +''
            @fonts = {}
            @colors = []
            @info = InfoFields.new
            @page_break_next = false
            @had_content = false
          end

          def detect_codepage
            match = @rtf.match(/\\ansicpg(\d+)/)
            @codepage = match[1].to_i if match
          end

          def codepage_encoding
            @codepage_encoding ||= begin
              Encoding.find("Windows-#{@codepage}")
            rescue ArgumentError
              begin
                Encoding.find("CP#{@codepage}")
              rescue ArgumentError
                Encoding::ISO_8859_1
              end
            end
          end

          def scan
            while @pos < @len
              byte = @rtf.getbyte(@pos)
              case byte
              when 123 then handle_group_open
              when 125 then handle_group_close
              when 92 then handle_backslash
              when 13, 10
                @pos += 1
              else
                handle_plain_byte(byte)
              end
            end
          end


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
            @colors << [color_component(text, 'red'), color_component(text, 'green'), color_component(text, 'blue')]
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
            pairs.to_h { |word, method_name| [word, method(method_name)] }
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


          def dispatch_control_word(word, param)
            return if handled_control_word?(word, param)

            dispatch_unicode_control(word, param)
          end

          def handled_control_word?(word, param)
            control_word_handlers(word, param).any?(&:call)
          end

          def control_word_handlers(word, param)
            [
              -> { handle_destination_control?(word) },
              -> { skipped_control_word?(word, param) },
              -> { handle_font_table_control?(word, param) },
              -> { handle_color_table_control?(word, param) },
              -> { handle_info_control?(word, param) },
              -> { append_named_character?(word) },
              -> { dispatch_character_control?(word, param) },
              -> { dispatch_paragraph_control?(word, param) },
              -> { dispatch_break_control?(word) },
            ]
          end

          def handle_destination_control?(word)
            was_ignorable = @ignorable_next
            @ignorable_next = false

            handler = destination_control_handlers[word]
            return handler.call(word) if handler
            return activate_skip_destination? if self.class::SKIP_DESTINATIONS.include?(word)
            return activate_skip_destination? if was_ignorable

            false
          end

          def destination_control_handlers
            @destination_control_handlers ||= {
              'fonttbl' => method(:activate_font_table_destination?),
              'colortbl' => method(:activate_color_table_destination?),
              'info' => method(:activate_info_destination?),
              'title' => method(:activate_info_text_destination?),
              'author' => method(:activate_info_text_destination?),
              'operator' => method(:activate_info_text_destination?),
              'company' => method(:activate_info_text_destination?),
              'creatim' => method(:activate_info_date_destination?),
              'revtim' => method(:activate_info_date_destination?),
              'printim' => method(:activate_info_date_destination?),
            }
          end

          def activate_font_table_destination?(_word)
            @in_fonttbl = true
            @fonttbl_depth = 0
            true
          end

          def activate_color_table_destination?(_word)
            @in_colortbl = true
            @colortbl_text = +''
            true
          end

          def activate_info_destination?(_word)
            @in_info = true
            @info_depth = 0
            true
          end

          def activate_info_text_destination?(word)
            return false unless @in_info

            @info_field = word
            @info_text = +''
            @info_date_parts = {}
            true
          end

          def activate_info_date_destination?(word)
            return false unless @in_info

            @info_field = word
            @info_date_parts = {}
            true
          end

          def activate_skip_destination?
            @skip_depth = 1
            true
          end

          def skipped_control_word?(_word, _param)
            @skip_depth.positive?
          end

          def handle_font_table_control?(word, param)
            return false unless @in_fonttbl && @fonttbl_depth.positive?
            return false unless word == 'f' && param

            @current_font_id = param
            true
          end

          def handle_color_table_control?(word, param)
            return false unless @in_colortbl

            handle_colortbl_word(word, param)
            true
          end

          def handle_info_control?(word, param)
            return false unless @in_info && @info_field

            handle_info_word(word, param)
            true
          end

          def append_named_character?(word)
            char = self.class::NAMED_CHARS[word]
            return false unless char

            append_char(char)
            true
          end

          def handle_colortbl_word(word, param)
            return unless %w[red green blue].include?(word)

            @colortbl_text << "#{word}#{param};"
          end

          def handle_info_word(word, param)
            return unless INFO_DATE_PARTS.include?(word)

            @info_date_parts[word] = param
          end


          def handle_backslash
            @pos += 1
            return if @pos >= @len

            symbol = @rtf.getbyte(@pos)
            return handle_hex_escape if symbol == 39
            return handle_literal_symbol(symbol) if literal_symbol?(symbol)

            control_handler = control_symbol_handlers[symbol]
            return control_handler.call if control_handler
            return read_control_word if letter_byte?(symbol)

            @pos += 1
          end

          def control_symbol_handlers
            @control_symbol_handlers ||= {
              42 => method(:mark_next_destination_ignorable),
              126 => method(:append_nonbreaking_space),
              45 => method(:skip_optional_hyphen),
              95 => method(:append_nonbreaking_hyphen),
            }
          end

          def handle_hex_escape
            @pos += 1
            return if @pos + 1 >= @len

            hex = @rtf[@pos, 2]
            @pos += 2
            return if @skip_depth.positive?

            append_hex_escape_byte(hex.to_i(16))
          rescue ArgumentError, RangeError, Encoding::CompatibilityError,
                 Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
            # Skip malformed hex escapes
          end

          def handle_literal_symbol(symbol)
            if @skip_depth.positive?
              @pos += 1
              return
            end

            append_char(symbol.chr)
            @pos += 1
          end

          def mark_next_destination_ignorable
            @pos += 1
            @ignorable_next = true
          end

          def append_nonbreaking_space
            @pos += 1
            append_char("\u00A0") unless @skip_depth.positive?
          end

          def skip_optional_hyphen
            @pos += 1
          end

          def append_nonbreaking_hyphen
            @pos += 1
            append_char("\u2011") unless @skip_depth.positive?
          end

          def read_control_word
            word = read_control_word_token
            param = read_optional_control_param
            consume_control_word_delimiter
            dispatch_control_word(word, param)
          end

          def read_control_word_token
            start = @pos
            @pos += 1 while @pos < @len && letter_byte?(@rtf.getbyte(@pos))
            @rtf[start...@pos]
          end

          def read_optional_control_param
            return nil unless signed_number_start?(@pos)

            start = @pos
            @pos += 1 if @rtf.getbyte(@pos) == 45
            @pos += 1 while @pos < @len && digit_byte?(@rtf.getbyte(@pos))
            @rtf[start...@pos].to_i
          end

          def consume_control_word_delimiter
            @pos += 1 if @pos < @len && @rtf.getbyte(@pos) == 32
          end

          def signed_number_start?(index)
            return false unless index < @len

            byte = @rtf.getbyte(index)
            byte == 45 || digit_byte?(byte)
          end

          def letter_byte?(byte)
            return false unless byte

            byte.between?(65, 90) || byte.between?(97, 122)
          end

          def digit_byte?(byte)
            byte&.between?(48, 57)
          end

          def literal_symbol?(byte)
            [123, 125, 92].include?(byte)
          end

          def append_hex_escape_byte(byte_val)
            return append_font_name_hex_byte(byte_val) if @in_fonttbl && @fonttbl_depth.positive?
            return @colortbl_text << byte_val.chr if @in_colortbl
            return append_info_hex_byte(byte_val) if @in_info && @info_field

            append_char(decode_codepage_byte(byte_val))
          end

          def append_font_name_hex_byte(byte_val)
            @current_font_name << decode_codepage_byte(byte_val)
          end

          def append_info_hex_byte(byte_val)
            @info_text << decode_codepage_byte(byte_val)
          end

          def decode_codepage_byte(byte_val)
            byte_val.chr(codepage_encoding).encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
          end

          def handle_unicode(param)
            return if param.nil? || @skip_depth.positive?

            append_unicode_codepoint(param)
            skip_unicode_fallback_bytes
          rescue ArgumentError, RangeError, Encoding::CompatibilityError
            skip_unicode_fallback_bytes
          end

          def append_unicode_codepoint(param)
            codepoint = param.negative? ? param + 65_536 : param
            return unless valid_unicode_codepoint?(codepoint)

            append_char([codepoint].pack('U'))
          end

          def handle_plain_byte(byte)
            @pos += 1
            return if @skip_depth.positive?
            return handle_font_table_plain_byte(byte) if @in_fonttbl && @fonttbl_depth.positive?
            return handle_color_table_plain_byte(byte) if @in_colortbl
            return handle_info_plain_byte(byte) if @in_info && @info_field

            @current_text << decode_codepage_byte(byte)
          rescue ArgumentError, RangeError, Encoding::CompatibilityError,
                 Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
            append_fallback_byte(byte)
          end

          def handle_font_table_plain_byte(byte)
            char = byte.chr
            @current_font_name << char unless char == ';'
          end

          def handle_color_table_plain_byte(byte)
            parse_color_entry if byte.chr == ';'
          end

          def handle_info_plain_byte(byte)
            @info_text << byte.chr
          end

          def append_char(str)
            @current_text << str
          end

          def valid_unicode_codepoint?(codepoint)
            return false unless codepoint.is_a?(Integer)
            return false unless codepoint.between?(0, 0x10FFFF)

            !(0xD800..0xDFFF).cover?(codepoint)
          end

          def skip_unicode_fallback_bytes
            skip_count = @uc_skip
            while skip_count.positive? && @pos < @len
              byte = @rtf.getbyte(@pos)
              break if byte.nil?
              break if self.class::BRACE_BYTES.include?(byte)

              @pos += byte == 92 && hex_escape_start?(@pos) ? 4 : 1
              skip_count -= 1
            end
          end

          def hex_escape_start?(index)
            index + 1 < @len && @rtf.getbyte(index + 1) == 39
          end

          def append_fallback_byte(byte)
            fallback = byte.to_i.chr(Encoding::BINARY).encode(
              'UTF-8',
              invalid: :replace,
              undef: :replace,
              replace: ''
            )
            @current_text << fallback unless fallback.empty?
          rescue ArgumentError, Encoding::CompatibilityError,
                 Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
            @current_text << "\uFFFD"
          end

        end
      end
    end
  end
end
