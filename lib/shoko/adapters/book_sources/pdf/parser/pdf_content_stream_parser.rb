# frozen_string_literal: true

require_relative 'pdf_content_stream_tokenizer'
require_relative 'pdf_text_fragment_decoder'

module Shoko
  module Adapters
    module BookSources
      module Pdf
        # Parses a decompressed PDF page content stream into line fragments with
        # x-position and style hints for downstream layout parsing.
        class PdfContentStreamParser
          OPERATOR_DISPATCH = {
            'Tf' => proc { handle_tf },
            'Tj' => proc { handle_tj },
            'TJ' => proc { handle_tj_array },
            "'" => proc { handle_quote },
            'Td' => proc { handle_td },
            'TD' => proc { handle_td },
            'Tm' => proc { handle_tm },
            'T*' => proc { flush_current_line },
            'BT' => proc { clear_operands },
            'ET' => proc { clear_operands },
          }.freeze

          def initialize(stream:, font_profiles:)
            @font_profiles = font_profiles || {}
            @tokenizer = PdfContentStreamTokenizer.new(stream)
            @decoder = PdfTextFragmentDecoder.new
            @raw_lines = []
            @current_line = +''
            @current_cmap = nil
            @current_font_italic = false
            @line_style_stats = empty_line_style_stats
            @last_y = nil
            @current_x = nil
            @operand_stack = []
          end

          # @return [Array<Hash>] [{ text:, x:, italic:, italic_ratio: }]
          def parse
            loop do
              token = @tokenizer.next_token
              break unless token
              break if token == :stop

              process_token(token)
            end

            flush_current_line
            @raw_lines
          end

          private

          def process_token(token)
            return handle_operator(token[:value]) if token[:type] == :operator

            @operand_stack << token
          end

          def handle_operator(operator_token)
            handler = OPERATOR_DISPATCH[operator_token]
            return instance_exec(&handler) if handler

            clear_operands
          end

          def clear_operands
            @operand_stack.clear
          end

          def handle_tf
            _size_op = @operand_stack.pop
            name_op = @operand_stack.pop
            return unless name_op && name_op[:type] == :name

            profile = @font_profiles[name_op[:value]] || {}
            @current_cmap = profile[:cmap]
            @current_font_italic = profile[:italic] ? true : false
          end

          def handle_tj
            str_op = @operand_stack.pop
            return unless str_op

            append_text_fragment(
              @current_line,
              string_operand_text(str_op),
              italic: @current_font_italic,
              style_stats: @line_style_stats
            )
          end

          def handle_tj_array
            arr_op = @operand_stack.pop
            return unless arr_op && arr_op[:type] == :array

            text = decode_tj_array(arr_op[:value], @current_cmap)
            append_text_fragment(@current_line, text, italic: @current_font_italic, style_stats: @line_style_stats)
          end

          def handle_quote
            flush_current_line
            str_op = @operand_stack.pop
            return unless str_op

            append_text_fragment(
              @current_line,
              string_operand_text(str_op),
              italic: @current_font_italic,
              style_stats: @line_style_stats
            )
          end

          def handle_td
            ty_op = @operand_stack.pop
            tx_op = @operand_stack.pop
            ty = ty_op && ty_op[:type] == :number ? ty_op[:value] : 0.0
            return unless ty.abs > 0.01

            flush_current_line
            @last_y = (@last_y || 0.0) + ty
            @current_x = tx_op && tx_op[:type] == :number ? tx_op[:value] : @current_x
          end

          def handle_tm
            operands = pop_n(@operand_stack, 6)
            new_x = numeric_operand_value(operands[4])
            new_y = numeric_operand_value(operands[5])
            flush_current_line if new_y && @last_y && (new_y - @last_y).abs > 0.5
            @last_y = new_y if new_y
            @current_x = new_x if new_x
          end

          def numeric_operand_value(operand)
            return nil unless operand && operand[:type] == :number

            operand[:value]
          end

          def string_operand_text(operand)
            case operand[:type]
            when :hex
              @decoder.decode_hex_string(operand[:value], @current_cmap)
            when :literal
              @decoder.decode_literal_string(operand[:value])
            else
              ''
            end
          end

          def flush_current_line
            return if @current_line.strip.empty?

            ratio = italic_ratio_for(@line_style_stats)
            @raw_lines << {
              text: @current_line.strip,
              x: @current_x,
              italic: italic_dominant?(@line_style_stats),
              italic_ratio: ratio,
            }
            @current_line = +''
            @line_style_stats = empty_line_style_stats
          end

          def append_text_fragment(current_line, text, italic:, style_stats:)
            fragment = text.to_s
            return if fragment.empty?

            current_line << fragment
            visible_chars = fragment.scan(/\S/).length
            return if visible_chars.zero?

            style_stats[:total_chars] += visible_chars
            style_stats[:italic_chars] += visible_chars if italic
          end

          def empty_line_style_stats
            { total_chars: 0, italic_chars: 0 }
          end

          def italic_ratio_for(style_stats)
            total = style_stats[:total_chars].to_i
            return 0.0 if total <= 0

            (style_stats[:italic_chars].to_f / total).round(4)
          end

          def italic_dominant?(style_stats)
            total = style_stats[:total_chars].to_i
            return false if total < 8

            italic_ratio_for(style_stats) >= 0.65
          end

          def pop_n(stack, count)
            result = stack.last(count)
            stack.pop([count, stack.size].min)
            result
          end

          def decode_tj_array(array_content, cmap)
            @decoder.decode_tj_array(array_content, cmap)
          end
        end
      end
    end
  end
end
