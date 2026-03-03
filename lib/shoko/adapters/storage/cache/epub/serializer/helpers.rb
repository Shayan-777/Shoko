# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      class EpubCache
        # Shared helpers used by the cache payload serializer/deserializer.
        module Serializer
          module_function

          def coerce_time(raw)
            return raw if raw.is_a?(Time)
            return nil unless raw

            Time.at(raw.to_f).utc
          rescue Shoko::Error
            raise
          end

          def value_for(obj, key)
            if obj.is_a?(Hash)
              obj[key] || obj[key.to_s]
            elsif obj.is_a?(Struct)
              obj[key]
            elsif obj.is_a?(Data)
              values = obj.to_h
              values[key] || values[key.to_s]
            end
          end

          def sanitize_display(text)
            string = text.to_s
            Shoko::Shared::TextSanitizer.sanitize(string, preserve_newlines: false,
                                                          preserve_tabs: false)
          rescue Shoko::Error
            string.to_s
          end
          private_class_method :sanitize_display

          def sanitize_content(text)
            string = text.to_s
            Shoko::Shared::TextSanitizer.sanitize(string, preserve_newlines: true,
                                                          preserve_tabs: true)
          rescue Shoko::Error
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
end
