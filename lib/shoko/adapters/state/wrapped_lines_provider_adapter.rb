# frozen_string_literal: true

require_relative '../../core/ports/wrapped_lines_provider'
require_relative '../../core/services/config_bridge'

module Shoko
  module Adapters::State
    # Adapter that provides wrapped lines using formatting service + document.
    class WrappedLinesProviderAdapter
      include Core::Ports::WrappedLinesProvider

      def initialize(formatting_service: nil, document: nil)
        @formatting_service = formatting_service
        @document = document
      end

      def wrapped_lines_for(chapter_index:, col_width:, lines_per_page:, config_reader:)
        return nil unless @formatting_service && @document

        config_bridge = Shoko::Core::Services::ConfigBridge.new(config_reader)
        @formatting_service.wrap_all(
          @document,
          chapter_index,
          col_width,
          config: config_bridge,
          lines_per_page: lines_per_page
        )
      rescue StandardError
        nil
      end
    end
  end
end
