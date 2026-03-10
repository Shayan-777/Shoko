# frozen_string_literal: true

require 'json'

module Shoko
  module Adapters
    module BookSources
      module Pdf
        # Parses raw layout payloads from JSON, nested JSON, or JSON-ish text.
        class PdfLayoutPayloadParser
          ARRAY_KEYS = %w[lines items runs].freeze
          NESTED_KEYS = %w[layout payload data].freeze

          def initialize(line_normalizer:)
            @line_normalizer = line_normalizer
          end

          # @return [Hash, nil] canonical payload ({ lines: [...] }) or nil
          def parse(text)
            parsed = parse_json_payload(text.to_s.strip)
            normalized = normalize_layout_payload(parsed)
            return normalized if normalized

            recover_layout_from_jsonish_text(text.to_s)
          end

          private

          def parse_json_payload(text)
            return nil if text.empty?
            return nil unless json_candidate?(text)

            payload = parse_json_safely(text)
            return nil if payload.nil?
            return payload unless payload.is_a?(String)

            parse_nested_json_payload(payload.to_s.strip, original: text)
          end

          def parse_nested_json_payload(nested, original:)
            return nested if nested.empty? || nested == original
            return nested unless nested.start_with?('{', '[', '"')

            parse_json_payload(nested)
          end

          def parse_json_safely(text)
            JSON.parse(text)
          rescue JSON::ParserError, TypeError
            invalid_json_payload
          end

          def invalid_json_payload
            nil
          end

          def json_candidate?(text)
            stripped = text.to_s.lstrip
            return false if stripped.empty?

            stripped.start_with?('{', '[', '"')
          end

          def normalize_layout_payload(payload)
            case payload
            when Array
              { lines: payload }
            when Hash
              normalize_hash_payload(payload)
            end
          end

          def normalize_hash_payload(payload)
            lines = extract_layout_lines(payload)
            return nil unless lines.is_a?(Array)

            { lines: lines }
          end

          def extract_layout_lines(payload)
            direct_lines = array_value(payload, ARRAY_KEYS)
            return direct_lines if direct_lines

            nested_lines = nested_payload_lines(payload)
            return nested_lines if nested_lines

            return [payload] if payload_line_hash?(payload)

            nil
          end

          def nested_payload_lines(payload)
            nested = first_nested_payload(payload)
            return nil unless nested

            normalize_layout_payload(nested)&.[](:lines)
          end

          def first_nested_payload(payload)
            NESTED_KEYS.each do |key|
              value = read_hash_key(payload, key)
              return value if value
            end
            nil
          end

          def array_value(payload, keys)
            keys.each do |key|
              value = read_hash_key(payload, key)
              return value if value.is_a?(Array)
            end
            nil
          end

          def payload_line_hash?(payload)
            return false unless payload.is_a?(Hash)

            text = @line_normalizer.extract_line_text(payload).strip
            !text.empty? || @line_normalizer.line_break?(payload)
          end

          def recover_layout_from_jsonish_text(text)
            return nil unless jsonish_text_candidate?(text)

            decoded = decode_jsonish_text_values(text)
            return nil if decoded.length < 2

            { lines: decoded.map { |value| { 'text' => value } } }
          end

          def jsonish_text_candidate?(text)
            text.include?('"text"') || text.include?('\\"text\\"')
          end

          def decode_jsonish_text_values(text)
            raw_values = text.scan(/"text"\s*:\s*"((?:\\.|[^"\\])*)"/).flatten
            raw_values = escaped_jsonish_values(text) if raw_values.empty?
            raw_values.filter_map { |value| decode_json_text_fragment(value) }
                      .map { |value| value.gsub(/\s+/, ' ').strip }
                      .reject(&:empty?)
          end

          def escaped_jsonish_values(text)
            text.scan(/\\"text\\"\s*:\s*\\"((?:\\\\.|[^"\\])*)\\"/).flatten
          end

          def decode_json_text_fragment(fragment)
            JSON.parse(%("#{fragment}"))
          rescue JSON::ParserError
            fragment.to_s
                    .gsub('\\\\', '\\')
                    .gsub('\\"', '"')
                    .gsub('\\n', "\n")
                    .gsub('\\r', "\r")
          end

          def read_hash_key(hash, key)
            return nil unless hash.is_a?(Hash)
            return hash[key] if hash.key?(key)

            symbol_key = key.to_sym
            return hash[symbol_key] if hash.key?(symbol_key)

            nil
          end
        end
      end
    end
  end
end
