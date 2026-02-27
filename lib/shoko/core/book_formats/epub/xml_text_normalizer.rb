# frozen_string_literal: true

require_relative '../../../shared/text_sanitizer'

module Shoko
  module Core
    module BookFormats
      module Epub
        # Normalizes XML or XHTML text into UTF-8 and sanitizes control sequences.
        module XmlTextNormalizer
          module_function

          def normalize(text)
            bytes = String(text).dup
            bytes.force_encoding(Encoding::BINARY)
            bytes = bytes.delete_prefix("\xEF\xBB\xBF".b)

            declared = bytes[/\A\s*<\?xml[^>]*encoding=["']([^"']+)["']/i, 1]
            encoding = begin
              declared ? Encoding.find(declared) : Encoding::UTF_8
            rescue StandardError
              Encoding::UTF_8
            end

            normalized = bytes.dup
            normalized.force_encoding(encoding)
            normalized = normalized.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
            normalized = normalized.delete_prefix("\uFEFF")
            Shoko::Shared::TextSanitizer.sanitize_xml_source(
              normalized,
              preserve_newlines: true,
              preserve_tabs: true
            )
          rescue StandardError
            Shoko::Shared::TextSanitizer.sanitize_xml_source(
              text.to_s,
              preserve_newlines: true,
              preserve_tabs: true
            )
          end
        end
      end
    end
  end
end
