# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port interface for chapter line wrapping collaborators used by pagination.
        module LineWrapper
          # Wrap the full chapter lines at the requested width.
          #
          # @param lines [Array<String>]
          # @param chapter_index [Integer]
          # @param width [Integer]
          # @param document [Object, nil]
          # @return [Array<String>]
          def wrap_lines(_lines, _chapter_index, _width, document: nil)
            raise NotImplementedError, "#{self.class} must implement #wrap_lines"
          end

          # Wrap a specific window from chapter lines.
          #
          # @param lines [Array<String>]
          # @param chapter_index [Integer]
          # @param width [Integer]
          # @param start [Integer]
          # @param length [Integer]
          # @param document [Object, nil]
          # @return [Array<String>]
          def wrap_window(*_args, document: nil)
            raise NotImplementedError, "#{self.class} must implement #wrap_window"
          end
        end
      end
    end
  end
end
