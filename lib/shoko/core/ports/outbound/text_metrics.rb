# frozen_string_literal: true

module Shoko
  module Core
    module Ports::Outbound
      # Port interface for text measurement and wrapping.
      module TextMetrics
        # Wrap a plain text line to the given width.
        #
        # @param line [String] input line
        # @param width [Integer] maximum line width
        # @return [Array<String>] wrapped segments
        def wrap_plain_text(_line, _width)
          raise NotImplementedError, "#{self.class} must implement #wrap_plain_text"
        end
      end
    end
  end
end
