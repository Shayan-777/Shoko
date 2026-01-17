# frozen_string_literal: true

module Shoko
  module Adapters::Storage
    class EpubCache
      # Shared helpers used by the cache payload serializer/deserializer.
      module Serializer
        module_function

        def coerce_time(raw)
          return raw if raw.is_a?(Time)
          return nil unless raw

          Time.at(raw.to_f).utc
        rescue StandardError
          nil
        end

        def value_for(obj, key)
          if obj.respond_to?(key)
            obj.public_send(key)
          elsif obj.respond_to?(:[])
            obj[key] || obj[key.to_s]
          end
        end

        def sanitize_display(text)
          string = text.to_s
          Shoko::Adapters::Output::Terminal::TerminalSanitizer.sanitize(string, preserve_newlines: false,
                                                                                preserve_tabs: false)
        rescue StandardError
          string.to_s
        end
        private_class_method :sanitize_display

        def sanitize_content(text)
          string = text.to_s
          Shoko::Adapters::Output::Terminal::TerminalSanitizer.sanitize(string, preserve_newlines: true,
                                                                                preserve_tabs: true)
        rescue StandardError
          string.to_s
        end
        private_class_method :sanitize_content

        def parse_json(raw, fallback_json:)
          return raw unless raw.is_a?(String)

          JSON.parse(raw.empty? ? fallback_json : raw)
        end
        private_class_method :parse_json

        def parse_json_array(raw)
          Array(parse_json(raw, fallback_json: '[]'))
        end
        private_class_method :parse_json_array

        def parse_json_hash(raw)
          parsed = parse_json(raw, fallback_json: '{}')
          parsed.is_a?(Hash) ? parsed : {}
        end
        private_class_method :parse_json_hash
      end
    end
  end
end
