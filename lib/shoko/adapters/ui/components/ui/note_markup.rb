# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          # Inline markup styling for annotation notes that — unlike the old
          # annotation-editor markup — keeps every marker character visible.
          #
          # Markers (one line at a time):
          #   *bold*  _underline_  -strike-  ~italic~
          #   "- " / "* " line prefix -> bullet item
          #   "1. " line prefix       -> numbered item
          #
          # The marker glyphs are rendered in a quiet +marker_fg+ (reduced visibility,
          # so they read as light scaffolding) while the spanned text gets the actual
          # attribute. Crucially the markers are NOT removed, so the styled string has
          # the exact same visible width as the raw text — which keeps the compose
          # editor's caret mapping trivial (1 raw char == 1 displayed column).
          module NoteMarkup
            # [attribute-on, attribute-off] SGR pairs (toggled, never a full reset, so
            # the surrounding background/foreground set by the caller is preserved).
            ATTR = {
              '*' => ["\e[1m", "\e[22m"],  # bold
              '_' => ["\e[4m", "\e[24m"],  # underline
              '-' => ["\e[9m", "\e[29m"],  # strikethrough
              '~' => ["\e[3m", "\e[23m"],  # italic
            }.freeze
            MARKERS = ATTR.keys.freeze

            # Leading bullet ("- "/"* ") or number ("12. ") list marker.
            LIST_PREFIX = /\A(\s*)(?:[*-]|\d{1,3}\.)\s/

            module_function

            # Style one already-wrapped line. +base_fg+ is the line's normal foreground
            # (markup restores to it after each span); +marker_fg+ is the quiet tone
            # for the marker glyphs themselves.
            def style_line(line, base_fg:, marker_fg:)
              text = line.to_s
              prefix = list_prefix_length(text)
              head = prefix.positive? ? "#{marker_fg}#{text[0, prefix]}#{base_fg}" : ''
              "#{head}#{style_inline(text[prefix..].to_s, base_fg, marker_fg)}"
            end

            def list_prefix_length(text)
              match = LIST_PREFIX.match(text)
              match ? match.end(0) : 0
            end

            # Wrap each matched marker pair's content with its attribute, leaving the
            # (dimmed) marker glyphs in place.
            def style_inline(text, base_fg, marker_fg)
              spans = find_spans(text)
              return text if spans.empty?

              out = +''
              index = 0
              while index < text.length
                span = spans.first
                out << emit_char(text, index, span: span, base_fg: base_fg, marker_fg: marker_fg)
                spans.shift if span && index == span[:close]
                index += 1
              end
              out
            end

            def emit_char(text, index, span:, base_fg:, marker_fg:)
              char = text[index]
              return "#{marker_fg}#{char}#{base_fg}#{span[:on]}" if span && index == span[:open]
              return "#{span[:off]}#{marker_fg}#{char}#{base_fg}" if span && index == span[:close]

              char
            end

            # Non-overlapping marker pairs across all marker kinds, left to right. A
            # pair needs non-space content and must not sit mid-word (so hyphens inside
            # words never strike), keeping styling unobtrusive and predictable.
            def find_spans(text)
              candidates = MARKERS.flat_map { |marker| marker_spans(text, marker) }
              pick_non_overlapping(candidates)
            end

            def marker_spans(text, marker)
              on, off = ATTR[marker]
              escaped = Regexp.escape(marker)
              regex = /(?<![[:alnum:]])#{escaped}(?=\S)[^#{escaped}\n]*?[^#{escaped}\s]#{escaped}(?![[:alnum:]])/
              spans = []
              text.to_enum(:scan, regex).each do
                match = Regexp.last_match
                spans << { open: match.begin(0), close: match.end(0) - 1, on: on, off: off }
              end
              spans
            end

            def pick_non_overlapping(candidates)
              last_close = -1
              candidates.sort_by { |span| [span[:open], span[:close]] }.each_with_object([]) do |span, kept|
                next if span[:open] <= last_close

                kept << span
                last_close = span[:close]
              end
            end
          end
        end
      end
    end
  end
end
