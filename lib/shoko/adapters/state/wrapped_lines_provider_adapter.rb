# frozen_string_literal: true

require_relative '../../core/ports/wrapped_lines_provider'

module Shoko
  module Adapters::State
    # Adapter that provides wrapped lines using formatting service + document.
    class WrappedLinesProviderAdapter
      include Core::Ports::WrappedLinesProvider

      def initialize(formatting_service: nil, document: nil, session_context: nil)
        @formatting_service = formatting_service
        @document = document
        @session_context = session_context
      end

      def wrapped_lines_for(chapter_index:, col_width:, lines_per_page:, config_reader:)
        document = current_document
        return nil unless @formatting_service && document

        @formatting_service.wrap_all(
          document,
          chapter_index,
          col_width,
          config: config_reader,
          lines_per_page: lines_per_page
        )
      rescue StandardError
        nil
      end

      private

      def current_document
        @session_context&.document || @document
      end
    end
  end
end
