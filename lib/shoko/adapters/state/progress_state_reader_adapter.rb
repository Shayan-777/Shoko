# frozen_string_literal: true

require_relative '../../core/ports/progress_state_reader'

module Shoko
  module Adapters::State
    # Application adapter implementing the ProgressStateReader port.
    # Reads progress restoration state from application state.
    class ProgressStateReaderAdapter
      include Core::Ports::ProgressStateReader

      def initialize(state)
        @state = state
      end

      # @param chapter_index [Integer] Chapter index
      # @return [Integer, nil] Line offset for the chapter
      def chapter_line_offset(chapter_index)
        progress = pending_progress
        return nil unless progress

        return progress[:line_offset] if progress[:chapter_index] == chapter_index

        nil
      end

      # @return [Hash, nil] Pending progress hash
      def pending_progress
        @state.get(%i[reader pending_progress])
      end
    end
  end
end
