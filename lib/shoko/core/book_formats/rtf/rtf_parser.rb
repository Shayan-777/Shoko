# frozen_string_literal: true

module Shoko
  module Core
    module BookFormats
      module Rtf
        # Single-pass RTF tokenizer and document model builder.
        #
        # Parses an RTF string into a structured DocumentModel containing
        # paragraphs with styled text runs, plus font/color tables and
        # document metadata from the \info group.
        class RtfParser
          Paragraph = Struct.new(:runs, :alignment, :first_indent, :space_before,
                                 :space_after, :page_break_before, keyword_init: true)
          TextRun = Struct.new(:text, :bold, :italic, :underline, :strikethrough,
                               :superscript, :subscript, :font_size, :font_index,
                               :color_index, keyword_init: true)
          DocumentModel = Struct.new(:paragraphs, :fonts, :colors, :info, keyword_init: true)
          InfoFields = Struct.new(:title, :author, :operator, :company, :creatim,
                                  :revtim, keyword_init: true)

          # Named special character control words
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

          # Destinations whose content should be completely ignored
          SKIP_DESTINATIONS = Set.new(%w[
            stylesheet listtable listoverridetable revtbl rsidtbl
            generator pnseclvl latentstyles colorschememapping
            themedata datastore mailmerge pgptbl xmlnstbl
            header footer headerl headerr headerf
            footerl footerr footerf
            pict object datafield fldinst mmathPr
          ]).freeze

          # Destinations inside \info that capture text
          INFO_DESTINATIONS = Set.new(%w[title author operator company]).freeze

          # @param rtf_string [String] raw RTF content
          # @param codepage [Integer] default codepage (overridden by \ansicpg)
          def initialize(rtf_string, codepage: 1252)
            @rtf = rtf_string.to_s
            @codepage = codepage
            @pos = 0
            @len = @rtf.length

            # State stack
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

            # Destination tracking
            @skip_depth = 0          # > 0 means we're inside a skipped destination
            @dest_stack = []         # stack of destination names
            @current_dest = nil      # current destination name
            @dest_text = +''         # accumulated text for parseable destinations
            @ignorable_next = false  # \* flag for next group

            # Font/color table parsing
            @in_fonttbl = false
            @fonttbl_depth = 0
            @current_font_id = nil
            @current_font_name = +''
            @in_colortbl = false
            @colortbl_text = +''

            # Info parsing
            @in_info = false
            @info_depth = 0
            @info_field = nil
            @info_text = +''
            @info_date_parts = {}

            # Output
            @paragraphs = []
            @current_runs = []
            @current_text = +''
            @fonts = {}
            @colors = []
            @info = InfoFields.new
            @page_break_next = false
            @had_content = false
          end

          # Parse the RTF string and return a DocumentModel.
          # @return [DocumentModel]
          def parse
            detect_codepage
            scan
            flush_paragraph
            DocumentModel.new(
              paragraphs: @paragraphs,
              fonts: @fonts,
              colors: @colors,
              info: @info
            )
          end

          private

          def detect_codepage
            if (m = @rtf.match(/\\ansicpg(\d+)/))
              @codepage = m[1].to_i
            end
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

          # Main scanning loop
          def scan
            while @pos < @len
              ch = @rtf.getbyte(@pos)
              case ch
              when 123 then handle_group_open   # {
              when 125 then handle_group_close   # }
              when 92  then handle_backslash     # \
              when 13, 10                        # CR, LF — ignored in RTF
                @pos += 1
              else
                handle_plain_byte(ch)
              end
            end
          end

          def handle_group_open
            @pos += 1
            push_state

            # Always track fonttbl/info depth, even inside skipped destinations
            if @in_fonttbl
              @fonttbl_depth += 1
              if @fonttbl_depth == 1 && @skip_depth == 0
                # New font entry — reset tracking
                @current_font_id = nil
                @current_font_name = +''
              end
            end

            @info_depth += 1 if @in_info

            if @skip_depth > 0
              @skip_depth += 1
              return
            end
          end

          def handle_group_close
            @pos += 1

            # Always track fonttbl/info depth, even inside skipped destinations
            fonttbl_closing = false
            info_closing = false

            if @in_fonttbl
              @fonttbl_depth -= 1
              fonttbl_closing = true
            end

            if @in_info
              @info_depth -= 1
              info_closing = true
            end

            if @skip_depth > 0
              @skip_depth -= 1
              @dest_text = +'' if @skip_depth == 0
              pop_state
              return
            end

            # Font entry closing (depth went from 1 to 0)
            if fonttbl_closing && @fonttbl_depth == 0
              finish_font_entry
              pop_state
              return
            end

            # Fonttbl group itself closing (depth went from 0 to -1)
            if fonttbl_closing && @fonttbl_depth < 0
              @in_fonttbl = false
              @fonttbl_depth = 0
              pop_state
              return
            end

            # Sub-group inside fonttbl (depth still > 0) — just pop state
            if fonttbl_closing && @fonttbl_depth > 0
              pop_state
              return
            end

            # Finish color table
            if @in_colortbl
              finish_colortbl
              @in_colortbl = false
              pop_state
              return
            end

            # Close a sub-group inside \info
            if info_closing && @info_depth >= 0
              if @info_field
                finish_info_field
                @info_field = nil
                @info_text = +''
                @info_date_parts = {}
              end
              pop_state
              return
            end

            # Info group itself closing (depth went negative)
            if info_closing && @info_depth < 0
              @in_info = false
              @info_depth = 0
              pop_state
              return
            end

            # Normal group close — flush text, pop state
            flush_text
            pop_state
          end

          def handle_backslash
            @pos += 1
            return if @pos >= @len

            ch = @rtf.getbyte(@pos)

            case ch
            when 39 # ' — hex escape
              handle_hex_escape
            when 123, 125, 92 # literal {, }, or \
              if @skip_depth > 0
                @pos += 1
                return
              end
              append_char(ch.chr)
              @pos += 1
            when 42 # * — ignorable destination marker
              @pos += 1
              @ignorable_next = true
            when 126 # ~ — non-breaking space
              @pos += 1
              append_char("\u00A0") unless @skip_depth > 0
            when 45 # - — optional hyphen
              @pos += 1
              # Skip optional hyphens
            when 95 # _ — non-breaking hyphen
              @pos += 1
              append_char("\u2011") unless @skip_depth > 0
            else
              if ch >= 65 && ch <= 90 || ch >= 97 && ch <= 122 # letter
                read_control_word
              else
                @pos += 1 # unknown control symbol, skip
              end
            end
          end

          def handle_hex_escape
            @pos += 1 # skip '
            return if @pos + 1 >= @len

            hex = @rtf[@pos, 2]
            @pos += 2

            return if @skip_depth > 0

            byte_val = hex.to_i(16)
            if @in_fonttbl && @fonttbl_depth > 0
              # Inside font name — accumulate raw
              @current_font_name << byte_val.chr(codepage_encoding).encode('UTF-8',
                invalid: :replace, undef: :replace, replace: '')
            elsif @in_colortbl
              @colortbl_text << byte_val.chr
            elsif @in_info && @info_field
              @info_text << byte_val.chr(codepage_encoding).encode('UTF-8',
                invalid: :replace, undef: :replace, replace: '')
            else
              char = byte_val.chr(codepage_encoding).encode('UTF-8',
                invalid: :replace, undef: :replace, replace: '')
              append_char(char)
            end
          rescue StandardError
            # Skip malformed hex escapes
          end

          def read_control_word
            start = @pos
            @pos += 1 while @pos < @len && (b = @rtf.getbyte(@pos)) &&
                            ((b >= 65 && b <= 90) || (b >= 97 && b <= 122))
            word = @rtf[start...@pos]

            # Optional numeric parameter
            param = nil
            if @pos < @len && (@rtf.getbyte(@pos) == 45 ||
               (@rtf.getbyte(@pos) >= 48 && @rtf.getbyte(@pos) <= 57))
              pstart = @pos
              @pos += 1 if @rtf.getbyte(@pos) == 45 # negative sign
              @pos += 1 while @pos < @len && @rtf.getbyte(@pos) >= 48 && @rtf.getbyte(@pos) <= 57
              param = @rtf[pstart...@pos].to_i
            end

            # Consume one trailing space delimiter
            if @pos < @len && @rtf.getbyte(@pos) == 32
              @pos += 1
            end

            dispatch_control_word(word, param)
          end

          def dispatch_control_word(word, param)
            # Check for destinations first
            if handle_destination(word, param)
              return
            end

            # If we're inside a skipped destination, ignore control words
            if @skip_depth > 0
              handle_skipped_control_word(word, param)
              return
            end

            # Font table entries
            if @in_fonttbl && @fonttbl_depth > 0 && word == 'f' && param
              @current_font_id = param
              return
            end

            # Color table entries
            if @in_colortbl
              handle_colortbl_word(word, param)
              return
            end

            # Info date parts
            if @in_info && @info_field
              handle_info_word(word, param)
              return
            end

            # Named characters
            if NAMED_CHARS.key?(word)
              append_char(NAMED_CHARS[word])
              return
            end

            case word
            # Character formatting
            when 'b'
              flush_text
              @bold = param != 0
            when 'i'
              flush_text
              @italic = param != 0
            when 'ul', 'uld', 'uldb', 'ulth', 'ulw', 'ulwave'
              flush_text
              @underline = param != 0
            when 'ulnone'
              flush_text
              @underline = false
            when 'strike'
              flush_text
              @strikethrough = param != 0
            when 'super'
              flush_text
              @superscript = true
              @subscript = false
            when 'sub'
              flush_text
              @subscript = true
              @superscript = false
            when 'nosupersub'
              flush_text
              @superscript = false
              @subscript = false
            when 'fs'
              flush_text
              @font_size = param || 24
            when 'f'
              flush_text
              @font_index = param || 0
            when 'cf'
              flush_text
              @color_index = param || 0
            when 'plain'
              flush_text
              reset_char_formatting

            # Paragraph formatting
            when 'pard'
              flush_text
              reset_para_formatting
            when 'qc'
              @alignment = :center
            when 'qj'
              @alignment = :justify
            when 'ql'
              @alignment = :left
            when 'qr'
              @alignment = :right
            when 'fi'
              @first_indent = param || 0
            when 'sb'
              @space_before = param || 0
            when 'sa'
              @space_after = param || 0

            # Paragraph/page breaks
            when 'par'
              flush_paragraph
            when 'page', 'pagebb'
              flush_paragraph
              @page_break_next = true
            when 'line'
              append_char("\n")
            when 'tab'
              append_char("\t")

            # Unicode
            when 'u'
              handle_unicode(param)
            when 'uc'
              @uc_skip = param || 1

            # Skip these common noise words
            when 'lang', 'langfe', 'langnp', 'langfenp', 'insrsid', 'charrsid',
                 'pararsid', 'sectrsid', 'rsid', 'cgrid', 'snext', 'itap',
                 'widctlpar', 'aspalpha', 'aspnum', 'faauto', 'adjustright',
                 'rin', 'lin', 'ri', 'li', 'rtlch', 'ltrch', 'loch', 'hich',
                 'dbch', 'af', 'afs', 'alang', 'ltrpar', 'rtlpar',
                 'fcs', 'cs', 'ds', 'ts', 'additive', 'ssemihidden',
                 'sectd', 'linex', 'sectdefaultcl', 'sftnbj',
                 'margl', 'margr', 'margt', 'margb',
                 'widowctrl', 'ftnbj', 'aenddoc', 'hyphhotz',
                 'noxlattoyen', 'expshrtn', 'noultrlspc', 'dntblnsbdb',
                 'nospaceforul', 'hyphcaps', 'horzdoc', 'dghspace',
                 'dgvspace', 'dghorigin', 'dgvorigin', 'dghshow', 'dgvshow',
                 'jcompress', 'viewkind', 'viewscale', 'viewzk',
                 'nolnhtadjtbl', 'rsidroot', 'fet', 'ansi', 'ansicpg',
                 'deff', 'stshfdbch', 'stshfloch', 'stshfhich', 'stshfbi',
                 'deflang', 'deflangfe', 'fcharset', 'fprq', 'panose',
                 'falt', 'froman', 'fswiss', 'fmodern', 'fnil', 'fdecor',
                 'fscript', 'fbidi', 'ftech', 'red', 'green', 'blue',
                 'highlight', 'cb', 'up', 'dn', 'expnd', 'expndtw',
                 'kerning', 'ltrmark', 'rtlmark', 'noproof', 'v',
                 'deleted', 'revised', 'revauth', 'revdttm', 'crauth',
                 'crdate', 'bkmkstart', 'bkmkend'
              # Intentionally ignored
            end
          end

          def handle_destination(word, _param)
            was_ignorable = @ignorable_next
            @ignorable_next = false

            case word
            when 'fonttbl'
              @in_fonttbl = true
              @fonttbl_depth = 0
              true
            when 'colortbl'
              @in_colortbl = true
              @colortbl_text = +''
              true
            when 'info'
              @in_info = true
              @info_depth = 0
              true
            when 'title', 'author', 'operator', 'company'
              if @in_info
                @info_field = word
                @info_text = +''
                @info_date_parts = {}
                true
              else
                false
              end
            when 'creatim', 'revtim', 'printim'
              if @in_info
                @info_field = word
                @info_date_parts = {}
                true
              else
                false
              end
            when *SKIP_DESTINATIONS
              @skip_depth = 1
              true
            else
              if was_ignorable
                # Unknown ignorable destination — skip it
                @skip_depth = 1
                true
              else
                false
              end
            end
          end

          def handle_skipped_control_word(_word, _param)
            # Inside a skipped destination, ignore all control words
          end

          def handle_colortbl_word(word, param)
            case word
            when 'red', 'green', 'blue'
              @colortbl_text << "#{word}#{param};"
            end
          end

          def handle_info_word(word, param)
            case word
            when 'yr', 'mo', 'dy', 'hr', 'min', 'sec'
              @info_date_parts[word] = param
            end
          end

          def handle_unicode(param)
            return if param.nil?
            return if @skip_depth > 0

            # param is a signed 16-bit value
            codepoint = param < 0 ? param + 65_536 : param
            append_char([codepoint].pack('U'))

            # Skip uc_skip bytes of ANSI fallback
            skip_count = @uc_skip
            while skip_count > 0 && @pos < @len
              b = @rtf.getbyte(@pos)
              if b == 92 # backslash — might be \' hex escape
                if @pos + 1 < @len && @rtf.getbyte(@pos + 1) == 39 # \'
                  @pos += 4 # skip \'XX
                else
                  break
                end
              elsif b == 123 || b == 125 # { or }
                break
              else
                @pos += 1
              end
              skip_count -= 1
            end
          rescue StandardError
            # Skip bad unicode
          end

          def handle_plain_byte(byte)
            @pos += 1

            if @skip_depth > 0
              return
            end

            if @in_fonttbl && @fonttbl_depth > 0
              ch = byte.chr
              if ch == ';'
                # End of font name
              else
                @current_font_name << ch
              end
              return
            end

            if @in_colortbl
              ch = byte.chr
              if ch == ';'
                parse_color_entry
              end
              return
            end

            if @in_info && @info_field
              @info_text << byte.chr
              return
            end

            ch = byte.chr(codepage_encoding).encode('UTF-8',
              invalid: :replace, undef: :replace, replace: '')
            @current_text << ch
          rescue StandardError
            @current_text << byte.chr rescue nil
          end

          def append_char(str)
            @current_text << str
          end

          def flush_text
            return if @current_text.empty?

            @current_runs << TextRun.new(
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

            # Skip truly empty paragraphs (no runs at all)
            if @current_runs.empty?
              return
            end

            # Check if all runs are whitespace-only
            combined = @current_runs.map(&:text).join
            if combined.strip.empty? && !@had_content
              @current_runs.clear
              return
            end

            @had_content = true

            @paragraphs << Paragraph.new(
              runs: @current_runs,
              alignment: @alignment,
              first_indent: @first_indent,
              space_before: @space_before,
              space_after: @space_after,
              page_break_before: @page_break_next
            )
            @current_runs = []
            @page_break_next = false
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

          # Only push/pop character-level formatting. Paragraph formatting
          # (alignment, indent, spacing) persists across groups and is only
          # changed by explicit control words like \pard, \qc, etc.
          def push_state
            @state_stack << [
              @bold, @italic, @underline, @strikethrough,
              @superscript, @subscript, @font_index, @font_size,
              @color_index, @uc_skip
            ]
          end

          def pop_state
            return if @state_stack.empty?

            @bold, @italic, @underline, @strikethrough,
              @superscript, @subscript, @font_index, @font_size,
              @color_index, @uc_skip = @state_stack.pop
          end

          def finish_font_entry
            return unless @current_font_id

            name = @current_font_name.strip.chomp(';').strip
            @fonts[@current_font_id] = name unless name.empty?
          end

          def parse_color_entry
            text = @colortbl_text
            @colortbl_text = +''

            r = text.match(/red(\d+)/)&.captures&.first&.to_i || 0
            g = text.match(/green(\d+)/)&.captures&.first&.to_i || 0
            b = text.match(/blue(\d+)/)&.captures&.first&.to_i || 0
            @colors << [r, g, b]
          end

          def finish_colortbl
            # Handle any remaining text
            parse_color_entry unless @colortbl_text.strip.empty?
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

            yr = parts['yr']
            mo = parts['mo']
            dy = parts['dy']
            return nil unless yr

            "#{yr}-#{mo.to_s.rjust(2, '0')}-#{dy.to_s.rjust(2, '0')}"
          end
        end
      end
    end
  end
end
