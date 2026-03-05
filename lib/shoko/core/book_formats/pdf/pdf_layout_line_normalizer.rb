# frozen_string_literal: true

module Shoko
  module Core
    module BookFormats
      module Pdf
        # Normalizes heterogeneous PDF layout payload lines into canonical hashes.
        class PdfLayoutLineNormalizer
          TEXT_KEYS = %i[text value line content].freeze
          SEGMENT_KEYS = %i[segments].freeze
          LINE_BREAK_KEYS = %i[break line_break newline new_line].freeze
          X_KEYS = %i[x left indent start_x].freeze
          ITALIC_RATIO_KEYS = %i[italic_ratio italic_pct italic_share].freeze
          STYLE_HASH_KEYS = %i[styles].freeze
          STYLE_TEXT_KEYS = %i[style font_style].freeze

          def normalize_lines(lines)
            Array(lines).map { |line| normalize_line_entry(line) }
          end

          def normalize_line_text(text)
            text.to_s
                .tr("\u00A0\u2007\u202F", ' ')
                .gsub(/[[:space:]]+/, ' ')
                .strip
          end

          def line_break?(hash)
            value = fetch_first_value(hash, LINE_BREAK_KEYS)
            truthy?(value)
          end

          def extract_line_text(hash)
            value = fetch_first_value(hash, TEXT_KEYS)
            return value.to_s if value

            segments = fetch_first_value(hash, SEGMENT_KEYS)
            return '' unless segments.is_a?(Array)

            segments.map { |segment| segment_text(segment) }.join
          end

          def extract_line_x(hash)
            parse_float(fetch_first_value(hash, X_KEYS))
          end

          def extract_line_italic_ratio(hash)
            parse_float(fetch_first_value(hash, ITALIC_RATIO_KEYS))
          end

          def line_italic?(hash, italic_ratio:)
            return italic_ratio >= 0.65 if italic_ratio

            explicit = explicit_italic(hash)
            return truthy?(explicit) unless explicit.nil?

            styles = fetch_first_value(hash, STYLE_HASH_KEYS)
            style_italic = style_italic_value(styles)
            return truthy?(style_italic) unless style_italic.nil?

            style_text_value(hash, styles).to_s.downcase.include?('italic')
          end

          private

          def normalize_line_entry(line)
            return normalize_string_line(line) if line.is_a?(String)

            normalize_hash_line(line.is_a?(Hash) ? line : {})
          end

          def normalize_string_line(line)
            text = normalize_line_text(line)
            return { break: true } if text.empty?

            { text: text, x: nil, italic: false, italic_ratio: nil }
          end

          def normalize_hash_line(hash)
            text = normalize_line_text(extract_line_text(hash))
            return { break: true } if line_break?(hash) || text.empty?

            italic_ratio = extract_line_italic_ratio(hash)
            {
              text: text,
              x: extract_line_x(hash),
              italic: line_italic?(hash, italic_ratio: italic_ratio),
              italic_ratio: italic_ratio,
            }
          end

          def fetch_first_value(hash, symbol_keys)
            return nil unless hash.is_a?(Hash)

            symbol_keys.each do |key|
              return hash[key] if hash.key?(key)

              string_key = key.to_s
              return hash[string_key] if hash.key?(string_key)
            end
            nil
          end

          def explicit_italic(hash)
            return hash[:italic] if hash.is_a?(Hash) && hash.key?(:italic)
            return hash['italic'] if hash.is_a?(Hash) && hash.key?('italic')

            nil
          end

          def style_italic_value(styles)
            return nil unless styles.is_a?(Hash)
            return styles[:italic] if styles.key?(:italic)
            return styles['italic'] if styles.key?('italic')

            nil
          end

          def style_text_value(hash, styles)
            value = fetch_first_value(hash, STYLE_TEXT_KEYS)
            return value if value
            return nil unless styles.is_a?(Hash)

            fetch_first_value(styles, STYLE_TEXT_KEYS)
          end

          def segment_text(segment)
            return segment.to_s unless segment.is_a?(Hash)

            fetch_first_value(segment, %i[text value])
          end

          def truthy?(value)
            value == true || value.to_s.casecmp('true').zero? || value.to_s == '1'
          end

          def parse_float(value)
            return nil if value.nil?
            return value.to_f if value.is_a?(Numeric)

            compact = value.to_s.strip
            return nil unless compact.match?(/\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)\z/)

            compact.to_f
          end
        end
      end
    end
  end
end
