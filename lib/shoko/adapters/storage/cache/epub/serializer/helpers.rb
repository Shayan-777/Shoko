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
          end

          def value_for(obj, key)
            case obj
            when Hash
              obj.transform_keys do |entry_key|
                entry_key.is_a?(String) ? entry_key.to_sym : entry_key
              end[key]
            when Struct
              obj[key]
            when Data
              values = obj.to_h
              values.transform_keys do |entry_key|
                entry_key.is_a?(String) ? entry_key.to_sym : entry_key
              end[key]
            end
          end

          def sanitize_display(text)
            Shoko::Shared::TextSanitizer.sanitize(text.to_s, preserve_newlines: false, preserve_tabs: false)
          end
          private_class_method :sanitize_display

          def sanitize_content(text)
            Shoko::Shared::TextSanitizer.sanitize(text.to_s, preserve_newlines: true, preserve_tabs: true)
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
