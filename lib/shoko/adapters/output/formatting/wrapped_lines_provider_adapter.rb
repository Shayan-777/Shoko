# frozen_string_literal: true

require 'shoko/application/ports/outbound/wrapped_lines_provider'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter that provides wrapped lines using formatting service + document.
        class WrappedLinesProviderAdapter
          include Application::Ports::Outbound::WrappedLinesProvider

          def initialize(formatting_service: nil, document: nil, launch_state: nil)
            @formatting_service = formatting_service
            @document = document
            @launch_state = launch_state
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
          end

          private

          def current_document
            @launch_state&.preloaded_document || @document
          end
        end
      end
    end
  end
end
