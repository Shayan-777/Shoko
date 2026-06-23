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
            'BT' => proc { handle_bt },
            'ET' => proc { clear_operands },
          }.freeze

          def initialize(stream:, font_profiles:)
            @font_profiles = font_profiles || {}
            @tokenizer = PdfContentStreamTokenizer.new(stream)
            @decoder = PdfTextFragmentDecoder.new
            @raw_lines = []
            @current_line = +''
            @current_cmap = nil
            @current_encoding_map = nil
            @current_base_encoding = nil
            @current_font_italic = false
            @current_font_bold = false
            @current_tf_size = nil
            @current_tm_scale = 1.0
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

          # Reset on BT: the text matrix returns to identity, so any size that
          # was being carried through the Tm vertical scale resets too.
          def handle_bt
            @current_tm_scale = 1.0
            clear_operands
          end

          def handle_tf
            size_op = @operand_stack.pop
            name_op = @operand_stack.pop
            return unless name_op && name_op[:type] == :name

            @current_tf_size = numeric_operand_value(size_op) || @current_tf_size
            profile = @font_profiles[name_op[:value]] || {}
            @current_cmap = profile[:cmap]
            @current_encoding_map = profile[:encoding_map]
            @current_base_encoding = profile[:base_encoding]
            @current_font_italic = profile[:italic] ? true : false
            @current_font_bold = profile[:bold] ? true : false
          end

          def handle_tj
            str_op = @operand_stack.pop
            return unless str_op

            append_text_fragment(@current_line, string_operand_text(str_op), style_stats: @line_style_stats)
          end

          def handle_tj_array
            arr_op = @operand_stack.pop
            return unless arr_op && arr_op[:type] == :array

            text = decode_tj_array(
              arr_op[:value],
              @current_cmap,
              byte_map: @current_encoding_map,
              base_encoding: @current_base_encoding
            )
            append_text_fragment(@current_line, text, style_stats: @line_style_stats)
          end

          def handle_quote
            flush_current_line
            str_op = @operand_stack.pop
            return unless str_op

            append_text_fragment(@current_line, string_operand_text(str_op), style_stats: @line_style_stats)
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
            scale = numeric_operand_value(operands[3])
            @current_tm_scale = scale.abs if scale && scale.abs > 0.0001
            flush_current_line if new_y && @last_y && (new_y - @last_y).abs > 0.5
            @last_y = new_y if new_y
            @current_x = new_x if new_x
          end

          # Effective text size = Tf size scaled by the text matrix's vertical
          # scale; many generators leave Tf at 1 and put the real size in Tm.
          def current_font_size
            return nil unless @current_tf_size

            (@current_tf_size * (@current_tm_scale || 1.0)).round(2)
          end

          def numeric_operand_value(operand)
            return nil unless operand && operand[:type] == :number

            operand[:value]
          end

          def string_operand_text(operand)
            case operand[:type]
            when :hex
              decode_font_string(:decode_hex_string, operand[:value])
            when :literal
              decode_font_string(:decode_literal_string, operand[:value])
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
              y: @last_y,
              italic: italic_dominant?(@line_style_stats),
              italic_ratio: ratio,
              bold: bold_dominant?(@line_style_stats),
              font_size: dominant_size(@line_style_stats),
            }
            @current_line = +''
            @line_style_stats = empty_line_style_stats
          end

          def append_text_fragment(current_line, text, style_stats:)
            fragment = normalize_fragment(text)
            return if fragment.empty?

            current_line << fragment
            visible_chars = fragment.scan(/\S/).length
            return if visible_chars.zero?

            style_stats[:total_chars] += visible_chars
            style_stats[:italic_chars] += visible_chars if @current_font_italic
            style_stats[:bold_chars] += visible_chars if @current_font_bold
            record_fragment_size(style_stats, visible_chars)
          end

          def record_fragment_size(style_stats, visible_chars)
            size = current_font_size
            return unless size

            style_stats[:size_chars][size] += visible_chars
          end

          def normalize_fragment(text)
            fragment = text.to_s.dup
            return fragment if fragment.encoding == Encoding::UTF_8 && fragment.valid_encoding?

            fragment.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
          rescue EncodingError
            fragment.force_encoding(Encoding::UTF_8).scrub('')
          end

          def empty_line_style_stats
            { total_chars: 0, italic_chars: 0, bold_chars: 0, size_chars: Hash.new(0) }
          end

          def bold_dominant?(style_stats)
            total = style_stats[:total_chars].to_i
            return false if total < 4

            (style_stats[:bold_chars].to_f / total) >= 0.6
          end

          # The size carried by the most characters on the line — robust against a
          # stray oversized glyph (e.g. a drop cap) skewing a body line.
          def dominant_size(style_stats)
            sizes = style_stats[:size_chars]
            return nil if sizes.empty?

            sizes.max_by { |_size, count| count }&.first
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

          def decode_tj_array(array_content, cmap, byte_map:, base_encoding:)
            @decoder.decode_tj_array(array_content, cmap, byte_map: byte_map, base_encoding: base_encoding)
          end

          def decode_font_string(method_name, value)
            @decoder.public_send(
              method_name,
              value,
              @current_cmap,
              byte_map: @current_encoding_map,
              base_encoding: @current_base_encoding
            )
          end
        end
      end
    end
  end
end
