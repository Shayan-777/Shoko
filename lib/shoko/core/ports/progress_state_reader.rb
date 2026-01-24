# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for reading progress restoration state.
      # Adapters implementing this interface provide access to progress data
      # without coupling core services to application state schema.
      #
      # @example Implementing this port
      #   class ProgressStateReaderAdapter
      #     include Shoko::Core::Ports::ProgressStateReader
      #
      #     def initialize(state)
      #       @state = state
      #     end
      #
      #     def chapter_line_offset(chapter_index)
      #       # Read from state
      #     end
      #   end
      module ProgressStateReader
        # Get the line offset for a specific chapter
        #
        # @param chapter_index [Integer] Chapter index
        # @return [Integer, nil] Line offset for the chapter
        def chapter_line_offset(chapter_index)
          raise NotImplementedError, "#{self.class} must implement #chapter_line_offset"
        end

        # Get the pending progress data
        #
        # @return [Hash, nil] Pending progress hash with chapter and line offset
        def pending_progress
          raise NotImplementedError, "#{self.class} must implement #pending_progress"
        end

        # Check if there is pending progress to restore
        #
        # @return [Boolean] True if there is pending progress
        def pending_progress?
          !pending_progress.nil?
        end
      end
    end
  end
end
