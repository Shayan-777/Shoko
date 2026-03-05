# frozen_string_literal: true

module Shoko
  module Core
    module BookFormats
      module Pdf
        module Reader
          # Parses values from PDF dictionaries for a given /Key.
          class DictionaryValueParser
            def parse(dict_text, key)
              rest = value_rest(dict_text, key)
              return nil unless rest

              parse_value(rest)
            end

            private

            def value_rest(dict_text, key)
              return nil unless dict_text

              pattern = %r{/#{Regexp.escape(key)}\s*}
              match = dict_text.match(pattern)
              return nil unless match

              dict_text[match.end(0)..]
            end

            def parse_value(rest)
              case rest[0]
              when '(' then extract_parenthesized(rest)
              when '<' then parse_angle_value(rest)
              when '[' then extract_array(rest)
              when '/' then parse_name_value(rest)
              else parse_numeric_or_reference(rest)
              end
            end

            def parse_angle_value(rest)
              rest[1] == '<' ? extract_nested_dict(rest) : extract_hex_string(rest)
            end

            def parse_name_value(rest)
              rest.match(%r{\A/([^\s/<>\[\]()]+)})&.[](1)
            end

            def parse_numeric_or_reference(rest)
              ref_match = rest.match(/\A(\d+)\s+(\d+)\s+R/)
              return "#{ref_match[1]} #{ref_match[2]} R" if ref_match

              rest.match(/\A-?[\d.]+/)&.[](0)
            end

            def extract_parenthesized(text)
              depth = 0
              i = 0
              while i < text.length
                case text[i]
                when '(' then depth += 1
                when ')'
                  depth -= 1
                  return text[1...i] if depth.zero?
                when '\\' then i += 1
                end
                i += 1
              end
              nil
            end

            def extract_hex_string(text)
              end_idx = text.index('>')
              return nil unless end_idx

              text[1...end_idx]
            end

            def extract_nested_dict(text)
              depth = 0
              i = 0
              while i < text.length - 1
                if text[i] == '<' && text[i + 1] == '<'
                  depth += 1
                  i += 2
                elsif text[i] == '>' && text[i + 1] == '>'
                  depth -= 1
                  return text[0..(i + 1)] if depth.zero?

                  i += 2
                else
                  i += 1
                end
              end
              text
            end

            def extract_array(text)
              depth = 0
              i = 0
              while i < text.length
                case text[i]
                when '[' then depth += 1
                when ']'
                  depth -= 1
                  return text[1...i] if depth.zero?
                end
                i += 1
              end
              nil
            end
          end
        end
      end
    end
  end
end
