# frozen_string_literal: true

require_relative '../../core/ports/ui_state_reader'

module Shoko
  module Adapters::State
    # Application adapter implementing the UIStateReader port.
    # Reads UI/display state from application state.
    class UIStateReaderAdapter
      include Core::Ports::UIStateReader

      def initialize(state)
        @state = state
      end

      # @return [Integer] Terminal width in columns
      def terminal_width
        @state.get(%i[ui terminal_width])
      end

      # @return [Integer] Terminal height in rows
      def terminal_height
        @state.get(%i[ui terminal_height])
      end

      # @return [String, nil]
      def loading_message
        @state.get(%i[ui loading_message])
      end

      # @return [Float, nil]
      def loading_progress
        @state.get(%i[ui loading_progress])
      end

      # @param width [Integer] Current terminal width
      # @param height [Integer] Current terminal height
      # @return [Boolean] True if dimensions differ from stored state
      def terminal_size_changed?(width, height)
        @state.terminal_size_changed?(width, height)
      end
    end
  end
end
