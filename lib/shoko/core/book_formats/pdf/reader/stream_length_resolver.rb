# frozen_string_literal: true

module Shoko
  module Core
    module BookFormats
      module Pdf
        module Reader
          # Resolves stream length from /Length (direct integer or indirect ref).
          class StreamLengthResolver
            def initialize(dict_value:, resolve_ref:, read_object_raw:)
              @dict_value = dict_value
              @resolve_ref = resolve_ref
              @read_object_raw = read_object_raw
            end

            def resolve(header)
              value = @dict_value.call(header, 'Length')
              return nil unless value

              text = value.to_s.strip
              return text.to_i if integer?(text)

              resolve_indirect_length(text)
            end

            private

            def integer?(text)
              text.match?(/\A-?\d+\z/)
            end

            def resolve_indirect_length(ref_text)
              ref_obj = @resolve_ref.call(ref_text)
              return nil unless ref_obj

              raw = @read_object_raw.call(ref_obj)
              return nil unless raw

              body = raw.sub(/\A.*?\bobj\b/m, '')
              parse_integer(body)
            end

            def parse_integer(text)
              match = text.to_s.match(/-?\d+/)
              match ? match[0].to_i : nil
            end
          end
        end
      end
    end
  end
end
