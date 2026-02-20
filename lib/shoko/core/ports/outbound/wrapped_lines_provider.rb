# frozen_string_literal: true

module Shoko
  module Core
    module Ports::Outbound
      # Port interface for retrieving wrapped content lines for a document.
      # Adapters implementing this interface hide formatting/document details
      # from core services.
      module WrappedLinesProvider
        # Fetch wrapped lines for a chapter.
        #
        # @param chapter_index [Integer] Chapter index
        # @param col_width [Integer] Column width
        # @param lines_per_page [Integer] Lines per page
        # @param config_reader [Object] Config reader dependency (duck-typed)
        # @return [Array, nil] Wrapped lines for the chapter, or nil if unavailable
        def wrapped_lines_for(chapter_index:, col_width:, lines_per_page:, config_reader:)
          raise NotImplementedError, "#{self.class} must implement #wrapped_lines_for"
        end
      end
    end
  end
end
