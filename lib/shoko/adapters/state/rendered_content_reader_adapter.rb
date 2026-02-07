# frozen_string_literal: true

require_relative '../../core/ports/rendered_content_reader'
require_relative 'selectors/reader_selectors'

module Shoko
  module Adapters::State
    # Application adapter implementing the RenderedContentReader port.
    # Reads rendered content from application state using ReaderSelectors.
    class RenderedContentReaderAdapter
      include Core::Ports::RenderedContentReader

      def initialize(state, render_registry: nil)
        @state = state
        @render_registry = render_registry
      end

      # Get the currently rendered lines
      # @return [Hash] Rendered lines data
      def rendered_lines
        Selectors::ReaderSelectors.rendered_lines(@state, render_registry: @render_registry)
      end
    end
  end
end
