# frozen_string_literal: true

module Shoko
  module Adapters
    module Translation
      # Splits text into sentence-sized segments for the translation engine,
      # which works on single sentences. Paragraph breaks (newlines) are
      # preserved as segment boundaries; overlong sentences are chunked at
      # phrase boundaries so they stay under the engine's input limit.
      module SentenceSplitter
        MAX_SEGMENT_BYTES = 1500

        # Sentence end: terminal punctuation (optionally followed by one
        # closing quote/bracket, which stays with its sentence), whitespace,
        # then an uppercase letter, digit or opening quote starting the next
        # sentence. Single-capital abbreviations ("J. Smith") do not split.
        BOUNDARY = /(?<=[.!?…]|[.!?…]["'”’»)\]])(?<![A-Z]\.)[ \t]+(?=["'“„‘«(\[]?[\p{Lu}\p{N}])/

        module_function

        # Returns [[segment, paragraph_break_after]] pairs.
        def segments(text)
          result = []
          paragraphs = text.to_s.split(/\n+/)
          paragraphs.each_with_index do |paragraph, index|
            pieces = split_paragraph(paragraph.strip)
            pieces.each_with_index do |piece, piece_index|
              last_in_paragraph = piece_index == pieces.length - 1
              break_after = last_in_paragraph && index < paragraphs.length - 1
              result << [piece, break_after]
            end
          end
          result
        end

        def split_paragraph(paragraph)
          return [] if paragraph.empty?

          paragraph.split(BOUNDARY).flat_map { |sentence| chunk(sentence.strip) }
                                   .reject(&:empty?)
        end

        # Hard-splits a sentence that exceeds the engine budget, preferring
        # commas/semicolons, then plain spaces, then a raw byte cut.
        def chunk(sentence)
          return [sentence] if sentence.bytesize <= MAX_SEGMENT_BYTES

          cut = cut_index(sentence)
          head = sentence[0...cut].strip
          tail = sentence[cut..].strip
          [head] + chunk(tail)
        end

        def cut_index(sentence)
          limit = byte_safe_limit(sentence)
          window = sentence[0...limit]
          phrase = window.rindex(/[,;:][ \t]/)
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
