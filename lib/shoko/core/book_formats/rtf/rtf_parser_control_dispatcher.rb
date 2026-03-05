# frozen_string_literal: true

module Shoko
  module Core
    module BookFormats
      module Rtf
        # Control-word dispatch and destination handling for RTF parser.
        module RtfParserControlDispatcher
          INFO_DATE_PARTS = Set.new(%w[yr mo dy hr min sec]).freeze

          private

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
        end
      end
    end
  end
end
