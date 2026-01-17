# frozen_string_literal: true

require_relative '../../core/ports/rendered_content_reader'
require_relative '../selectors/reader_selectors'

module Shoko
  module Application
    module Adapters
      # Application adapter implementing the RenderedContentReader port.
      # Reads rendered content from application state using ReaderSelectors.
      class RenderedContentReaderAdapter
        include Core::Ports::RenderedContentReader

        def initialize(state)
          @state = state
        end

        # Get the currently rendered lines
        # @return [Hash] Rendered lines data
        def rendered_lines
          Selectors::ReaderSelectors.rendered_lines(@state)
        end
      end
    end
  end
end
