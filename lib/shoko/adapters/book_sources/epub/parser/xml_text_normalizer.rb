# frozen_string_literal: true

require_relative '../../../../shared/text_sanitizer'

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Normalizes XML or XHTML text into UTF-8 and sanitizes control sequences.
        module XmlTextNormalizer
          module_function

          def normalize(text)
            bytes = normalized_xml_bytes(text)
            encoding = declared_encoding_for(bytes)
            sanitize_xml_source(decode_xml_text(bytes, encoding))
          rescue Shoko::Error
            sanitize_xml_source(text.to_s)
          end

          def normalized_xml_bytes(text)
            bytes = String(text).dup
            bytes.force_encoding(Encoding::BINARY)
            bytes.delete_prefix("\xEF\xBB\xBF".b)
          end

          def declared_encoding_for(bytes)
            declared = bytes[/\A\s*<\?xml[^>]*encoding=["']([^"']+)["']/i, 1]
            declared ? Encoding.find(declared) : Encoding::UTF_8
          rescue Shoko::Error
            Encoding::UTF_8
          end

          def decode_xml_text(bytes, encoding)
            normalized = bytes.dup
            normalized.force_encoding(encoding)
            normalized.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
                      .delete_prefix("\uFEFF")
          end

          def sanitize_xml_source(text)
            Shoko::Shared::TextSanitizer.sanitize_xml_source(
              text,
              preserve_newlines: true,
              preserve_tabs: true
            )
          end
        end
      end
    end
  end
end
