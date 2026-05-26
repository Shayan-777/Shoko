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
        end
      end
    end
  end
end
