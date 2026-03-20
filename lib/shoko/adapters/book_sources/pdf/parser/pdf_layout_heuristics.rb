# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Pdf
        # Heuristics for classifying PDF layout lines and attribution signatures.
        class PdfLayoutHeuristics
          ATTRIBUTION_STOPWORDS = %w[
            copyright published printing edition registered offices group books ltd inc foundation
          ].freeze

          def heading_line?(text, align, context)
            compact = text.to_s.strip
            return false unless heading_candidate_base?(compact, context)
            return true if compact.match?(/\A[IVXLCDM\d]+\z/i)

            heading_alignment_candidate?(compact, align)
          end

          def epigraph_line?(line, align, content_index, previous_kind:, next_line:, preamble_open:)
            return false unless epigraph_window?(line, content_index, preamble_open)
            return true if epigraph_attribution_continuation?(line, align, previous_kind)
            return true if quote_line_followed_by_attribution?(line[:text], next_line, content_index)

            epigraph_style_or_alignment?(line, align, content_index)
          end

          def body_line_candidate?(line, align, content_index, previous_kind:, next_line:)
            base_context = {
              align: align,
              content_index: content_index,
              previous_kind: previous_kind,
              next_line: next_line,
            }
            return false unless body_line_candidate_base?(line, base_context)

            compact = line[:text].to_s.strip
            return false if attribution_signature_line?(compact)
            return false if compact.match?(/\A[IVXLCDM\d]+\z/i)

            compact.split(/\s+/).length >= 8 || compact.length >= 48
          end

          def attribution_signature_line?(text)
            compact = text.to_s.strip
            return false if compact.empty? || compact.length > 80
            return true if author_source_signature?(compact)

            ratio_data = attribution_ratio_data(compact)
            return false unless ratio_data

            ratio_based_attribution?(ratio_data)
          end

          private

          def heading_candidate_base?(compact, context)
            return false if compact.empty?
            return false unless context[:prev_break] || context[:next_break]
            return false if attribution_signature_line?(compact)
            return false if context[:next_line] && attribution_signature_line?(context[:next_line][:text])

            !likely_attribution_context?(compact, prev_line: context[:prev_line])
          end

          def heading_alignment_candidate?(compact, align)
            return false unless %i[center right].include?(align)
            return false if compact.length > 64
            return false if compact.split(/\s+/).length > 8

            !compact.match?(/[.!?:;]\z/)
          end

          def epigraph_window?(line, content_index, preamble_open)
            preamble_open && content_index <= 40 && epigraph_length_candidate?(line[:text])
          end

          def epigraph_style_or_alignment?(line, align, content_index)
            return true if content_index <= 24 && italic_dominant?(line)
            return true if align == :right
            return false if align == :left

            italic_dominant?(line)
          end

          def epigraph_attribution_continuation?(line, align, previous_kind)
            attribution_signature_line?(line[:text]) && previous_kind == :epigraph && align != :left
          end

          def author_source_signature?(text)
            parts = text.to_s.strip.split(',').map(&:strip).reject(&:empty?)
            return false if parts.length < 2

            author = parts.first
            return false unless valid_author_signature?(author)

            source = parts[1..].join(',').strip
            valid_source_signature?(source)
          end

          def valid_author_signature?(author)
            return false if author.length < 4 || author.length > 48
            return false if author.match?(%r{\d|[:;/]})

            words = author.split(/\s+/)
            return false unless words.length.between?(2, 6)
            return false if words.any? { |word| attribution_author_stopword?(word) }

            author_like_words = words.count { |word| author_name_token?(word) }
            author_like_words >= [words.length - 1, 1].max
          end

          def valid_source_signature?(source)
            return false if source.empty? || source.length > 72
            return false if source.match?(/\A\d+\z/)

            true
          end

          def attribution_author_stopword?(token)
            normalized = token.to_s.downcase.gsub(/[^a-z]/, '')
            return false if normalized.empty?

            ATTRIBUTION_STOPWORDS.include?(normalized)
          end

          def author_name_token?(token)
            compact = token.to_s.gsub(/\A[“"'(]+|[”"').]+\z/, '')
            return false if compact.empty?

            compact.match?(/\A[A-Z]{2,}(?:-[A-Z]{2,})*\z/) ||
              compact.match?(/\A[A-Z][a-z]+(?:[-'’][A-Z][a-z]+)*\z/) ||
              compact.match?(/\A[A-Z]\z/)
          end

          def likely_attribution_context?(text, prev_line:)
            return false unless prev_line

            compact = text.to_s.strip
            return false unless compact.include?(',')
            return false unless sentence_like_epigraph_line?(prev_line[:text])

            compact.length <= 80 && compact.split(/\s+/).length <= 10
          end

          def quote_line_followed_by_attribution?(text, next_line, content_index)
            return false unless content_index <= 24
            return false unless next_line
            return false unless sentence_like_epigraph_line?(text)

            attribution_signature_line?(next_line[:text])
          end

          def sentence_like_epigraph_line?(text)
            compact = text.to_s.strip
            return false if compact.empty?
            return false unless compact.match?(/[.!?]\z/)

            word_count = compact.split(/\s+/).length
            word_count.between?(4, 20)
          end

          def epigraph_length_candidate?(text)
            compact = text.to_s.strip
            return false if compact.empty?

            word_count = compact.split(/\s+/).length
            word_count <= 24 && compact.length <= 200
          end

          def italic_dominant?(line)
            ratio = line[:italic_ratio]
            return ratio.to_f >= 0.65 if ratio

            !!line[:italic]
          end

          def body_line_candidate_base?(line, context)
            return false unless context[:content_index] <= 160
            return false unless context[:align] == :left
            return false if context[:previous_kind] == :epigraph
            return false if context[:content_index] <= 24 && italic_dominant?(line)
            if quote_line_followed_by_attribution?(line[:text], context[:next_line], context[:content_index])
              return false
            end

            !line[:text].to_s.strip.empty?
          end

          def attribution_ratio_data(compact)
            letters = compact.scan(/[A-Za-z]/)
            return nil if letters.empty?

            {
              ratio: uppercase_ratio(letters),
              has_delimiter: compact.include?(',') || compact.include?(' - ') || compact.include?(' — '),
              has_year: compact.match?(/\b(1[5-9]\d{2}|20\d{2})\b/),
            }
          end

          def ratio_based_attribution?(ratio_data)
            ratio = ratio_data[:ratio]
            return true if ratio >= 0.58
            return true if ratio >= 0.40 && ratio_data[:has_delimiter]

            ratio >= 0.30 && ratio_data[:has_delimiter] && ratio_data[:has_year]
          end

          def uppercase_ratio(letters)
            uppercase_count = letters.count { |char| char == char.upcase }
            uppercase_count.to_f / letters.length
          end
        end
      end
    end
  end
end
