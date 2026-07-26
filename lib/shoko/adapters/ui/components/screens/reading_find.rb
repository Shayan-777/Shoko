# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Locates a query in an article's reading stream.
          #
          # Matching runs over the same character stream selection uses, so a
          # match is expressible as a span and can be highlighted, counted, and
          # scrolled to with the machinery that is already there.
          #
          # Case-insensitive and literal: a reader looking for "Drohne" means
          # the word, not a pattern, so regex metacharacters in the query match
          # themselves.
          module ReadingFind
            module_function

            # @param stream [String] the article's selectable text
            # @param query [String]
            # @return [Array<Range>] match ranges, in reading order
            def matches(stream, query)
              needle = query.to_s
              return [] if needle.strip.empty?

              found = []
              cursor = 0
              while (at = stream.downcase.index(needle.downcase, cursor))
                found << (at...(at + needle.length))
                cursor = at + 1
              end
              found
            end

            # The match a reader is currently on, wrapping at either end so
            # n/N cycle rather than dead-ending.
            # @return [Integer] index into +matches+
            def wrap_index(index, total)
              return 0 if total <= 0

              index.to_i % total
            end

            # The scroll offset that brings a match into view, moving as little
            # as possible: a match already on screen does not scroll at all.
            def scroll_to(match, lines, scroll:, visible:)
              row = lines.index { |line| line.selectable? && match.first < line.end_index }
              return scroll unless row

              window = [visible, 1].max
              return row if row < scroll
              return row - window + 1 if row >= scroll + window

              scroll
            end
          end
        end
      end
    end
  end
end
