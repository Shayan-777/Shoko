# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Pdf
        # Tokenizer for PDF page content streams.
        # Produces operand/operator tokens for PdfContentStreamParser.
        class PdfContentStreamTokenizer
          DELIMITER_REGEX = %r{[\s/<>\[\]()]}
          private_constant :DELIMITER_REGEX

          def initialize(stream)
            @stream = stream.to_s
            @pos = 0
          end

          # @return [Hash, nil, Symbol] token hash, nil to skip token, or :stop
          def next_token
            skip_whitespace
            return nil if @pos >= @stream.length

            token_for_char(@stream[@pos])
          end

          private

          def token_for_char(char)
            case char
            when '/' then parse_name_token
            when '<' then parse_angle_token
            when '(' then parse_literal_token
            when '[' then parse_array_token
            when '-', '+', '.', '0'..'9' then parse_number_token
            else parse_operator_token
            end
          end

          def skip_whitespace
            @pos += 1 while @pos < @stream.length && " \t\r\n".include?(@stream[@pos])
          end

          def parse_name_token
            name_end = @stream.index(DELIMITER_REGEX, @pos + 1) || @stream.length
            token = { type: :name, value: @stream[(@pos + 1)...name_end] }
            @pos = name_end
            token
          end

          def parse_angle_token
            return parse_hex_token unless @stream[@pos + 1] == '<'

            @pos = skip_nested_dict(@stream, @pos)
            nil
          end

          def parse_hex_token
            end_pos = @stream.index('>', @pos + 1)
            return :stop unless end_pos

            token = { type: :hex, value: @stream[(@pos + 1)...end_pos] }
            @pos = end_pos + 1
            token
          end

          def parse_literal_token
            token = { type: :literal, value: extract_literal_string(@stream, @pos) }
            @pos = skip_literal_string(@stream, @pos)
            token
          end

          def parse_array_token
            array_end = find_matching_bracket(@stream, @pos)
            return :stop unless array_end

            token = { type: :array, value: @stream[(@pos + 1)...array_end] }
            @pos = array_end + 1
            token
          end

          def parse_number_token
            token_end = @stream.index(/[^\d.eE\-+]/, @pos + 1) || @stream.length
            token = { type: :number, value: @stream[@pos...token_end].to_f }
            @pos = token_end
            token
          end

          def parse_operator_token
            token_end = @stream.index(DELIMITER_REGEX, @pos) || @stream.length
            op = @stream[@pos...token_end]
            @pos = token_end
            return nil if op.empty?

            { type: :operator, value: op }
          end

          def extract_literal_string(stream, pos)
            depth = 0
            i = pos
            while i < stream.length
              case stream[i]
              when '(' then depth += 1
              when ')'
                depth -= 1
                return stream[(pos + 1)...i] if depth.zero?
              when '\\'
                i += 1
              end
              i += 1
            end
            ''
          end

          def skip_literal_string(stream, pos)
            depth = 0
            i = pos
            while i < stream.length
              case stream[i]
              when '(' then depth += 1
              when ')'
                depth -= 1
                return i + 1 if depth.zero?
              when '\\'
                i += 1
              end
              i += 1
            end
            stream.length
          end

          def find_matching_bracket(stream, pos)
            depth = 0
            i = pos
            while i < stream.length
              case stream[i]
              when '[' then depth += 1
              when ']'
                depth -= 1
                return i if depth.zero?
              when '('
                i = skip_literal_string(stream, i)
                next
              end
              i += 1
            end
            nil
          end

          def skip_nested_dict(stream, pos)
            depth = 0
            i = pos
            while i < stream.length - 1
              if stream[i] == '<' && stream[i + 1] == '<'
                depth += 1
                i += 2
              elsif stream[i] == '>' && stream[i + 1] == '>'
                depth -= 1
                return i + 2 if depth.zero?

                i += 2
              else
                i += 1
              end
            end
            stream.length
          end
        end
      end
    end
  end
end
