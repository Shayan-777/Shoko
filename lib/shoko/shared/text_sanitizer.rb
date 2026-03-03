# frozen_string_literal: true

module Shoko
  module Shared
    # Sanitizes untrusted text for safe display.
    #
    # Removes ANSI/VT control sequences (OSC/DCS/CSI/etc.) and drops C0/C1 control
    # characters to prevent escape injection and layout corruption.
    #
    # This is a pure text-processing utility with no I/O or external dependencies.
    module TextSanitizer
      module_function

      # Pre-sanitizer for XML/XHTML sources before feeding them to an XML parser.
      #
      # Some EPUBs (and malicious inputs) include numeric character references to
      # disallowed control characters (e.g. `&#x1b;` / `&#27;`), which can cause
      # REXML to raise parse errors. To keep parsing resilient, this method:
      # - Decodes *numeric* references for C0/C1/DEL into real codepoints so the
      #   control-sequence scanner can remove the entire escape sequence.
      # - Drops numeric references to codepoints that are invalid in XML 1.0.
      #
      # It intentionally does not decode non-control references (e.g. `&#60;`)
      # because doing so can change document structure before parsing.
      def sanitize_xml_source(text, preserve_newlines: true, preserve_tabs: true)
        return '' if text.nil?

        str = coerce_utf8(String(text))
        return '' if str.empty?

        pre = decode_control_numeric_references(str)
        sanitize(pre, preserve_newlines: preserve_newlines, preserve_tabs: preserve_tabs)
      rescue Shoko::Error
        sanitize(text.to_s, preserve_newlines: preserve_newlines, preserve_tabs: preserve_tabs)
      end

      # @param text [String,nil]
      # @param preserve_newlines [Boolean] keep `\n` (and normalize `\r` to `\n`)
      # @param preserve_tabs [Boolean] keep `\t`
      # @return [String] UTF-8 string safe for display
      def sanitize(text, preserve_newlines: false, preserve_tabs: false)
        return '' if text.nil?

        str = String(text)
        return '' if str.empty?

        str = coerce_utf8(str)
        cps = str.codepoints
        return '' if cps.empty?

        out = +''
        out.force_encoding(Encoding::UTF_8)

        i = 0
        while i < cps.length
          cp = cps[i]

          case cp
          when 0x1B # ESC
            i = skip_esc_sequence(cps, i + 1)
            next
          when 0x9B # CSI (8-bit)
            i = skip_csi_sequence(cps, i + 1)
            next
          when 0x9D # OSC (8-bit)
            i = skip_osc_sequence(cps, i + 1, c1_variant: true)
            next
          when 0x90, 0x98, 0x9E, 0x9F # DCS, SOS, PM, APC (8-bit)
            i = skip_string_sequence(cps, i + 1, c1_variant: true)
            next
          end

          if cp == 0x0A # \n
            out << (preserve_newlines ? "\n" : ' ')
            i += 1
            next
          end

          if cp == 0x0D # \r
            out << (preserve_newlines ? "\n" : ' ')
            i += 1
            next
          end

          if cp == 0x09 # \t
            out << (preserve_tabs ? "\t" : ' ')
            i += 1
            next
          end

          if control_codepoint?(cp)
            i += 1
            next
          end

          out << cp
          i += 1
        end

        out
      rescue Shoko::Error
        String(text).encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
      end

      # Input filter for single-character text entry (search fields, editors).
      # Prevents inserting C0/C1 control characters and DEL.
      def printable_char?(key)
        return false unless key.is_a?(String)
        return false unless key.length == 1

        cp = key.ord
        return false if cp < 0x20
        return false if cp == 0x7F
        return false if cp.between?(0x80, 0x9F)

        true
      rescue Shoko::Error
        false
      end

      def coerce_utf8(str)
        return str if str.encoding == Encoding::UTF_8 && str.valid_encoding?

        str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
      rescue Shoko::Error
        str.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
      end
      private_class_method :coerce_utf8

      def control_codepoint?(codepoint)
        return true if codepoint < 0x20
        return true if codepoint == 0x7F
        return true if codepoint.between?(0x80, 0x9F)

        false
      end
      private_class_method :control_codepoint?

      def skip_esc_sequence(codepoints, index)
        return codepoints.length if index >= codepoints.length

        lead = codepoints[index]
        case lead
        when 0x5B # '[' CSI
          skip_csi_sequence(codepoints, index + 1)
        when 0x5D # ']' OSC
          skip_osc_sequence(codepoints, index + 1, c1_variant: false)
        when 0x50, 0x58, 0x5E, 0x5F # 'P' DCS, 'X' SOS, '^' PM, '_' APC
          skip_string_sequence(codepoints, index + 1, c1_variant: false)
        else
          # 2-byte escape sequence (ESC + final byte)
          index + 1
        end
      end
      private_class_method :skip_esc_sequence

      def skip_csi_sequence(codepoints, index)
        while index < codepoints.length
          cp = codepoints[index]
          index += 1
          # Final byte is 0x40..0x7E
          break if cp.between?(0x40, 0x7E)
        end
        index
      end
      private_class_method :skip_csi_sequence

      def skip_osc_sequence(codepoints, index, c1_variant:)
        while index < codepoints.length
          cp = codepoints[index]

          return index + 1 if cp == 0x07 # BEL

          return index + 2 if !c1_variant && cp == 0x1B && codepoints[index + 1] == 0x5C # ESC \

          return index + 1 if c1_variant && cp == 0x9C # ST (8-bit)

          # Allow ESC \ as terminator even for 8-bit variants (robustness).
          return index + 2 if cp == 0x1B && codepoints[index + 1] == 0x5C

          index += 1
        end
        index
      end
      private_class_method :skip_osc_sequence

      def skip_string_sequence(codepoints, index, c1_variant:)
        while index < codepoints.length
          cp = codepoints[index]

          return index + 1 if c1_variant && cp == 0x9C # ST

          return index + 2 if cp == 0x1B && codepoints[index + 1] == 0x5C # ESC \

          index += 1
        end
        index
      end
      private_class_method :skip_string_sequence

      def decode_control_numeric_references(str)
        # Hex numeric references
        out = str.gsub(/&#x([0-9A-Fa-f]+);/) do |match|
          cp = Regexp.last_match(1).to_i(16)
          replacement_for_xml_numeric_ref(cp, match)
        end

        # Decimal numeric references
        out.gsub(/&#(\d+);/) do |match|
          cp = Regexp.last_match(1).to_i
          replacement_for_xml_numeric_ref(cp, match)
        end
      end
      private_class_method :decode_control_numeric_references

      def replacement_for_xml_numeric_ref(codepoint, original)
        return '' unless codepoint.is_a?(Integer)

        # Decode control characters so the escape-sequence scanner can remove the
        # full sequence (e.g. ESC + '[' + ... + 'm').
        return [codepoint].pack('U') if codepoint < 0x20 || codepoint == 0x7F || codepoint.between?(0x80, 0x9F)

        # Drop codepoints that are not valid in XML 1.0.
        xml_allowed_codepoint?(codepoint) ? original : ''
      rescue Shoko::Error
        ''
      end
      private_class_method :replacement_for_xml_numeric_ref

      def xml_allowed_codepoint?(codepoint)
        return true if [0x09, 0x0A, 0x0D].include?(codepoint)
        return true if codepoint.between?(0x20, 0xD7FF)
        return true if codepoint.between?(0xE000, 0xFFFD)
        return true if codepoint.between?(0x10000, 0x10FFFF)

        false
      end
      private_class_method :xml_allowed_codepoint?
    end
  end
end
