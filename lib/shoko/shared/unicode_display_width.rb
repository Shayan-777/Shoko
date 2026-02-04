# frozen_string_literal: true

require 'zlib'

module Shoko
  module Shared
    # Internal Unicode display width helper used to avoid external gem dependencies.
    module UnicodeDisplayWidth
      DEFAULT_AMBIGUOUS = 1
      INITIAL_DEPTH = 0x10000
      ASCII_NON_ZERO_REGEX = /[\0\x05\a\b\n-\x0F]/
      ASCII_NON_ZERO_STRING = "\0\x05\a\b\n-\x0F"
      ASCII_BACKSPACE = "\b"
      AMBIGUOUS_MAP = { 1 => :WIDTH_ONE, 2 => :WIDTH_TWO }.freeze
      FIRST_AMBIGUOUS = { WIDTH_ONE: 768, WIDTH_TWO: 161 }.freeze
      NOT_COMMON_NARROW_REGEX = {
        WIDTH_ONE: /[^\u{10}-\u{2FF}]/m,
        WIDTH_TWO: /[^\u{10}-\u{A1}]/m,
      }.freeze

      DATA_FILE = File.expand_path('unicode_display_width/display_width.marshal.gz', __dir__)

      INDEX = File.open(DATA_FILE, 'rb') do |file|
        serialized_data = Zlib::GzipReader.new(file).read
        serialized_data.force_encoding(Encoding::BINARY)
        Marshal.load(serialized_data)
      end

      def self.decompress_index(index, level)
        index.flat_map do |value|
          if level.positive?
            if value.is_a?(Array)
              value[15] ||= nil
              decompress_index(value, level - 1)
            else
              decompress_index([value] * 16, level - 1)
            end
          elsif value.is_a?(Array)
            value[15] ||= nil
            value
          else
            [value] * 16
          end
        end
      end

      FIRST_4096 = {
        WIDTH_ONE: decompress_index(INDEX[:WIDTH_ONE][0][0], 1),
        WIDTH_TWO: decompress_index(INDEX[:WIDTH_TWO][0][0], 1),
      }.freeze

      REGEX_TEXT_PRESENTATION = /[\p{Emoji}&&\P{EPres}]/
      REGEX_EMOJI_KEYCAP = /[#*0-9]\u{FE0F}\u{20E3}/
      REGEX_EMOJI_VS16 = Regexp.union(
        Regexp.new("#{REGEX_TEXT_PRESENTATION.source}(?<![#*0-9])\u{FE0F}"),
        REGEX_EMOJI_KEYCAP
      ).freeze
      REGEX_EMOJI_ALL_SEQUENCES = Regexp.union(
        /.[\u{1F3FB}-\u{1F3FF}\u{FE0F}]?(\u{200D}.[\u{1F3FB}-\u{1F3FF}\u{FE0F}]?)+|.[\u{1F3FB}-\u{1F3FF}]/,
        REGEX_EMOJI_KEYCAP
      ).freeze
      REGEX_EMOJI_ALL_SEQUENCES_AND_VS16 = Regexp.union(
        REGEX_EMOJI_ALL_SEQUENCES,
        REGEX_EMOJI_VS16
      ).freeze

      module_function

      def width(string, ambiguous: DEFAULT_AMBIGUOUS, emoji: :all)
        return 0 if string.nil?

        str = normalize_string(string)
        return 0 if str.empty?

        return width_ascii(str) if str.ascii_only?

        ambiguous_key = AMBIGUOUS_MAP.fetch(ambiguous) do
          raise ArgumentError, 'ambiguous width must be 1 or 2'
        end

        return str.size unless str.match?(NOT_COMMON_NARROW_REGEX[ambiguous_key])

        width = 0

        if emoji != :none
          emoji_width_value, str = emoji_width(str)
          width += emoji_width_value

          return width + str.size unless str.match?(NOT_COMMON_NARROW_REGEX[ambiguous_key])
        end

        index_full = INDEX[ambiguous_key]
        index_low = FIRST_4096[ambiguous_key]
        first_ambiguous = FIRST_AMBIGUOUS[ambiguous_key]

        str.each_codepoint do |codepoint|
          if codepoint > 15 && codepoint < first_ambiguous
            width += 1
          elsif codepoint < 0x1001
            width += index_low[codepoint] || 1
          else
            d = INITIAL_DEPTH
            w = index_full[codepoint / d]
            w = w[(codepoint %= d) / (d /= 16)] while w.is_a?(Array)
            width += w || 1
          end
        end

        width.negative? ? 0 : width
      end

      def normalize_string(string)
        str = string.to_s
        str = str.dup if str.frozen?

        if str.encoding == Encoding::BINARY && !str.dup.force_encoding(Encoding::UTF_8).valid_encoding?
          str.force_encoding(Encoding::BINARY)
        end

        return str if str.encoding == Encoding::UTF_8

        str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      end
      private :normalize_string

      def width_ascii(string)
        if string.match?(ASCII_NON_ZERO_REGEX)
          res = string.delete(ASCII_NON_ZERO_STRING).bytesize - string.count(ASCII_BACKSPACE)
          return res.negative? ? 0 : res
        end

        string.bytesize
      end
      private :width_ascii

      def emoji_width(string)
        width = 0
        remaining = string.gsub(REGEX_EMOJI_ALL_SEQUENCES_AND_VS16) do
          width += 2
          ''
        end
        [width, remaining]
      end
      private :emoji_width
    end
  end
end
