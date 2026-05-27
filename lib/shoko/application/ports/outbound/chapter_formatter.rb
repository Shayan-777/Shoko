# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port interface for chapter formatting collaborators used by pagination.
        module ChapterFormatter
          # Return wrapped formatted lines for a chapter window.
          #
          # @param document [Object]
          # @param chapter_index [Integer]
          # @param width [Integer]
          # @param offset [Integer]
          # @param length [Integer]
          # @param config [Object, nil]
          # @param lines_per_page [Integer, nil]
          # @return [Array]
          def wrap_window(_document, _chapter_index, _width, offset:, length:, config: nil, lines_per_page: nil)
            raise NotImplementedError, "#{self.class} must implement #wrap_window"
          end

          # Return wrapped formatted lines for an entire chapter.
          #
          # @param document [Object]
          # @param chapter_index [Integer]
          # @param width [Integer]
          # @param config [Object, nil]
          # @param lines_per_page [Integer, nil]
          # @return [Array]
          def wrap_all(_document, _chapter_index, _width, config: nil, lines_per_page: nil)
            raise NotImplementedError, "#{self.class} must implement #wrap_all"
          end

          # Return the chapter's parsed plain-text lines (no width-based
          # wrapping). Used by pagination/search/wrapping consumers that
          # previously read `chapter.lines` populated by an adapter-level
          # back-write mutation. The formatter owns parsing; the chapter
          # struct stays read-only with respect to plain_lines.
          #
          # @param document [Object]
          # @param chapter_index [Integer]
          # @return [Array<String>] plain-text lines for the chapter
          def plain_lines_for(_document, _chapter_index)
            raise NotImplementedError, "#{self.class} must implement #plain_lines_for"
          end
        end
      end
    end
  end
end
