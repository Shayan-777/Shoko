# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Pdf
        module Importer
          # Shared title decoding helpers for PDF outlines and fallback metadata.
          module TitleDecoding
            private

            def sanitize(text)
              Shoko::Shared::TextSanitizer.sanitize(text.to_s, preserve_newlines: false, preserve_tabs: false)
            rescue Shoko::Error
              text.to_s
            end

            def decode_outline_title(raw_title)
              sanitize(decode_pdf_hex_text(raw_title))
            end

            def decode_pdf_hex_text(raw_title)
              text = raw_title.to_s.strip
              return text unless text.match?(/\A(?:[0-9A-Fa-f]{2}\s*)+\z/)

              decode_pdf_hex_bytes([text.delete(" \t\r\n")].pack('H*'))
            rescue ArgumentError, EncodingError
              raw_title.to_s
            end

            def decode_pdf_hex_bytes(bytes)
              return bytes_to_utf8(bytes.byteslice(2..)) if bytes.start_with?("\xFE\xFF".b)
              if bytes.start_with?("\xFF\xFE".b)
                return bytes_to_utf8(bytes.byteslice(2..), encoding: Encoding::UTF_16LE)
              end
              if bytes.include?("\x00".b) && bytes.bytesize.even?
                return bytes_to_utf8(bytes, encoding: Encoding::UTF_16BE)
              end

              bytes_to_utf8(bytes)
            end

            def bytes_to_utf8(bytes, encoding: Encoding::UTF_8)
              return '' unless bytes

              bytes.dup.force_encoding(encoding).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
            rescue EncodingError
              bytes.dup.force_encoding(Encoding::UTF_8).scrub('')
            end

            def fallback_title(path)
              fallback_title_from_path(path) { |text| sanitize(text) }
            end
          end
        end
      end
    end
  end
end
