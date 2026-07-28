# frozen_string_literal: true

module Shoko
  module Adapters
    module Translation
      # Unicode-aware, separator-preserving sentence segmentation for the local
      # engine. Every returned pair is [translatable_text, exact_separator].
      # Rejoining text + separator therefore preserves paragraph structure and
      # intentional whitespace while keeping separators out of neural requests.
      module SentenceSplitter
        MAX_SEGMENT_BYTES = 1500

        CLOSERS = /["'”’»)\]]*/
        LATIN_TERMINAL = /[.!?…]+#{CLOSERS}/
        CJK_TERMINAL = /[。！？]+#{CLOSERS}/
        CANDIDATE =
          /(?<latin>#{LATIN_TERMINAL})(?<space>[ \t]+|(?=\n|\z))|(?<cjk>#{CJK_TERMINAL})(?<cjk_space>[ \t]*)|(?<line>\n+)/
        ABBREVIATIONS = %w[
          mr mrs ms dr prof sr jr st vs etc e.g i.e approx no fig al
        ].freeze

        module_function

        def segments(text)
          source = text.to_s
          result = []
          cursor = 0
          source.to_enum(:scan, CANDIDATE).each do
            match = Regexp.last_match
            if match[:line]
              append_segment(result, source[cursor...match.begin(0)], match[:line])
              cursor = match.end(0)
              next
            end

            terminal_end = match[:latin] ? match.end(:latin) : match.end(:cjk)
            piece = source[cursor...terminal_end]
            next if abbreviation_boundary?(piece)

            separator = match[:space] || match[:cjk_space] || ''
            append_segment(result, piece, separator)
            cursor = match.end(0)
          end
          append_segment(result, source[cursor..].to_s, '')
          result
        end

        def append_segment(result, text, separator)
          content = text.to_s
          if content.strip.empty?
            result[-1][1] << separator.to_s if result.any?
            return
          end

          pieces = chunk(content)
          pieces.each_with_index do |piece, index|
            result << [piece, index == pieces.length - 1 ? separator.to_s.dup : ' ']
          end
        end

        def abbreviation_boundary?(piece)
          return false unless piece.end_with?('.')

          token = piece[/(\p{L}+)\.\z/, 1].to_s
          return true if token.length == 1

          ABBREVIATIONS.include?(token.downcase)
        end

        # Hard-splits a sentence that exceeds the engine budget, preferring
        # phrase punctuation, then whitespace, then a UTF-8-safe character cut.
        def chunk(sentence)
          return [sentence] if sentence.bytesize <= MAX_SEGMENT_BYTES

          cut = cut_index(sentence)
          head = sentence[0...cut].strip
          tail = sentence[cut..].to_s.strip
          return [sentence] if head.empty? || tail.empty?

          [head] + chunk(tail)
        end

        def cut_index(sentence)
          limit = byte_safe_limit(sentence)
          window = sentence[0...limit]
          phrase = window.rindex(/[,;:，；：][ \t]/)
          return phrase + 1 if phrase&.positive?

          space = window.rindex(/[ \t]/)
          return space if space&.positive?

          limit
        end

        def byte_safe_limit(sentence)
          count = 0
          sentence.each_char.with_index do |char, index|
            count += char.bytesize
            return index if count > MAX_SEGMENT_BYTES
          end
          sentence.length
        end
      end
    end
  end
end
