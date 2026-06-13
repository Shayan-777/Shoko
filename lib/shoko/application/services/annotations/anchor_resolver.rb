# frozen_string_literal: true

require 'shoko/core/models/document_anchor'

module Shoko
  module Application
    module Services
      module Annotations
        # Locates DocumentAnchors in the current layout, and captures new
        # anchors from text selected in that layout.
        #
        # Matching is whitespace-insensitive: the chapter's wrapped lines are
        # folded into a normalized stream (case-folded, all whitespace
        # dropped) with a per-character map back to (line offset, char index),
        # so a quote wrapped differently at another width still matches.
        # Repeated quotes are disambiguated by the anchor's normalized
        # prefix/suffix context and its stored position ratio.
        class AnchorResolver
          CONTEXT_CHARS = 24
          STREAM_CACHE_LIMIT = 8
          RESOLUTION_CACHE_LIMIT = 64
          CONTEXT_MATCH_SCORE = 8

          # A located anchor under the current layout. +line_spans+ map the
          # quote onto wrapped lines: each entry carries the chapter-relative
          # wrapped line offset, the char range within that line, and the
          # line's text (so painters can verify they are highlighting the
          # text the span was resolved against).
          Resolution = Data.define(:start_line_offset, :line_spans)
          LineSpan = Data.define(:line_offset, :start_char, :end_char, :line_text)

          # Normalized chapter text plus per-character maps back to the wrapped
          # lines it was built from.
          Stream = Data.define(:lines, :normalized, :line_nos, :char_nos)
          private_constant :Stream

          def initialize(chapter_stream_source:, logger: nil)
            @chapter_stream_source = chapter_stream_source
            @logger = logger
            @streams = {}
            @resolutions = {}
          end

          # Locate an anchor in the current layout.
          #
          # @param anchor [Core::Models::DocumentAnchor, Hash, nil]
          # @return [Resolution, nil]
          def resolve(anchor, chapter_index:)
            document_anchor = coerce(anchor)
            return nil if document_anchor.nil? || document_anchor.empty?

            stream = stream_for(chapter_index)
            return nil unless stream

            cached_resolution(document_anchor, chapter_index, stream) do
              locate(document_anchor, stream)
            end
          end

          # The wrapped line offset an anchor lands on under the current
          # layout, or nil when it cannot be located.
          def line_offset_for(anchor, chapter_index:)
            resolve(anchor, chapter_index: chapter_index)&.start_line_offset
          end

          # Capture an anchor for +quote+ as selected in the current layout.
          # +line_offset_hint+ (the selection's wrapped line offset) pins the
          # intended occurrence when the quote repeats within the chapter.
          #
          # @return [Core::Models::DocumentAnchor]
          def capture_quote(quote:, chapter_index:, line_offset_hint: nil)
            text = quote.to_s
            stream = stream_for(chapter_index)
            occurrence = stream && find_capture_occurrence(stream, normalize(text), line_offset_hint)
            return fallback_quote_anchor(text, stream, line_offset_hint) unless occurrence

            build_quote_anchor(text, stream, occurrence)
          end

          # Capture a position-only anchor (page/chapter notes without a
          # quote) from a wrapped line offset in the current layout.
          #
          # @return [Core::Models::DocumentAnchor]
          def capture_position(chapter_index:, line_offset:)
            stream = stream_for(chapter_index)
            total = stream&.lines&.length.to_i
            position = total.positive? ? stream_ratio(line_offset.to_i.clamp(0, total - 1), total) : nil
            Shoko::Core::Models::DocumentAnchor.from_h(position: position)
          end

          private

          def build_quote_anchor(text, stream, occurrence)
            normalized = stream.normalized
            Shoko::Core::Models::DocumentAnchor.from_h(
              quote: text,
              prefix: normalized[[occurrence.begin - CONTEXT_CHARS, 0].max...occurrence.begin],
              suffix: normalized[occurrence.end...(occurrence.end + CONTEXT_CHARS)],
              position: stream_ratio(occurrence.begin, normalized.length)
            )
          end

          def coerce(anchor)
            return anchor if anchor.is_a?(Shoko::Core::Models::DocumentAnchor)

            Shoko::Core::Models::DocumentAnchor.from_h(anchor)
          end

          def stream_for(chapter_index)
            fetch = @chapter_stream_source.fetch(chapter_index)
            return nil unless fetch

            cached = @streams[fetch.signature]
            return cached if cached

            stream = build_stream(fetch.lines)
            evict(@streams, STREAM_CACHE_LIMIT)
            @streams[fetch.signature] = stream
          end

          def build_stream(lines)
            normalized = +''
            line_nos = []
            char_nos = []
            lines.each_with_index do |line, line_no|
              line.to_s.each_char.with_index do |char, char_no|
                next if char.match?(/\s/)

                normalized << char.downcase
                line_nos << line_no
                char_nos << char_no
              end
            end
            Stream.new(lines: lines, normalized: normalized.freeze, line_nos: line_nos, char_nos: char_nos)
          end

          def cached_resolution(anchor, chapter_index, stream)
            key = [chapter_index.to_i, stream.object_id, anchor]
            return de_cache(@resolutions[key]) if @resolutions.key?(key)

            resolution = yield
            evict(@resolutions, RESOLUTION_CACHE_LIMIT)
            @resolutions[key] = resolution || :none
            resolution
          end

          def de_cache(value)
            value == :none ? nil : value
          end

          def evict(cache, limit)
            cache.shift while cache.length >= limit
          end

          def locate(anchor, stream)
            return locate_quote(anchor, stream) if anchor.quote?

            locate_position(anchor, stream)
          end

          def locate_quote(anchor, stream)
            needle = normalize(anchor.quote)
            return nil if needle.empty?

            occurrence = best_occurrence(stream, needle, anchor)
            return nil unless occurrence

            Resolution.new(
              start_line_offset: stream.line_nos[occurrence.begin],
              line_spans: spans_for(stream, occurrence)
            )
          end

          def locate_position(anchor, stream)
            total = stream.lines.length
            return nil unless anchor.position? && total.positive?

            offset = (anchor.position * total).round.clamp(0, total - 1)
            Resolution.new(start_line_offset: offset, line_spans: [])
          end

          def best_occurrence(stream, needle, anchor)
            occurrences(stream.normalized, needle)
              .max_by { |occurrence| [occurrence_score(stream, occurrence, anchor), -occurrence.begin] }
          end

          def occurrences(haystack, needle)
            found = []
            offset = 0
            while (index = haystack.index(needle, offset))
              found << (index...(index + needle.length))
              offset = index + 1
              break if found.length >= 200
            end
            found
          end

          def occurrence_score(stream, occurrence, anchor)
            context_score(stream.normalized, occurrence, anchor) - position_distance(stream, occurrence, anchor)
          end

          def context_score(normalized, occurrence, anchor)
            score = 0
            score += CONTEXT_MATCH_SCORE if prefix_match?(normalized, occurrence, anchor.prefix)
            score += CONTEXT_MATCH_SCORE if suffix_match?(normalized, occurrence, anchor.suffix)
            score
          end

          def prefix_match?(normalized, occurrence, prefix)
            return false if prefix.nil?

            normalized[[occurrence.begin - prefix.length, 0].max...occurrence.begin] == prefix
          end

          def suffix_match?(normalized, occurrence, suffix)
            return false if suffix.nil?

            normalized[occurrence.end, suffix.length].to_s == suffix
          end

          # 0..1 penalty: occurrences nearer the stored position win ties.
          def position_distance(stream, occurrence, anchor)
            return 0.0 unless anchor.position?

            length = stream.normalized.length
            return 0.0 unless length.positive?

            ((occurrence.begin.to_f / length) - anchor.position).abs
          end

          def spans_for(stream, occurrence)
            occurrence
              .group_by { |stream_index| stream.line_nos[stream_index] }
              .map { |line_offset, stream_indexes| line_span(stream, line_offset, stream_indexes) }
          end

          def line_span(stream, line_offset, stream_indexes)
            LineSpan.new(
              line_offset: line_offset,
              start_char: stream.char_nos[stream_indexes.first],
              end_char: stream.char_nos[stream_indexes.last] + 1,
              line_text: stream.lines[line_offset].to_s
            )
          end

          # At capture time the selection's line offset is live, so the
          # nearest occurrence to it is the one the user selected.
          def find_capture_occurrence(stream, needle, line_offset_hint)
            return nil if needle.empty?

            found = occurrences(stream.normalized, needle)
            return found.first unless line_offset_hint

            hint = line_offset_hint.to_i
            found.min_by { |occurrence| (stream.line_nos[occurrence.begin].to_i - hint).abs }
          end

          # The rendered selection text can differ from the chapter stream in
          # edge cases (clipped lines at the viewport border); keep the quote
          # with a coarse position so resolution can still try later layouts.
          def fallback_quote_anchor(text, stream, line_offset_hint)
            total = stream&.lines&.length.to_i
            position = if total.positive? && line_offset_hint
                         stream_ratio(line_offset_hint.to_i.clamp(0, total - 1), total)
                       end
            Shoko::Core::Models::DocumentAnchor.from_h(quote: text, position: position)
          end

          def stream_ratio(index, total)
            return nil unless total.to_i.positive?

            (index.to_f / total).clamp(0.0, 1.0)
          end

          def normalize(text)
            text.to_s.downcase.gsub(/\s+/, '')
          end
        end
      end
    end
  end
end
