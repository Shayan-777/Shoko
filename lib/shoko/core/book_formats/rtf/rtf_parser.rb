# frozen_string_literal: true

require_relative 'rtf_parser_byte_handlers'
require_relative 'rtf_parser_control_actions'
require_relative 'rtf_parser_control_dispatcher'
require_relative 'rtf_parser_group_handlers'
require_relative 'rtf_parser_output_helpers'

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
          include RtfParserOutputHelpers
          include RtfParserGroupHandlers
          include RtfParserControlActions
          include RtfParserControlDispatcher
          include RtfParserByteHandlers

          Paragraph = Struct.new(:runs, :alignment, :first_indent, :space_before,
                                 :space_after, :page_break_before)
          TextRun = Struct.new(:text, :bold, :italic, :underline, :strikethrough,
                               :superscript, :subscript, :font_size, :font_index,
                               :color_index)
          DocumentModel = Struct.new(:paragraphs, :fonts, :colors, :info)
          InfoFields = Struct.new(:title, :author, :operator, :company, :creatim,
                                  :revtim)

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
            DocumentModel.new(
              paragraphs: @paragraphs,
              fonts: @fonts,
              colors: @colors,
              info: @info
            )
          end

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
        end
      end
    end
  end
end
