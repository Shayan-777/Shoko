# frozen_string_literal: true

module Shoko
  module Application
    module State
      module Schema
        # Application-owned reader process-state schema fragment.
        #
        # Owns the slice of `state[:reader]` that drives application orchestration
        # while a book is open: which mode the reader is in, lifecycle flags,
        # pending intents waiting for runtime conditions, and loading mirrors.
        # These are read by use cases and workflows to decide control flow.
        module ReaderProcess
          PARTITION = :reader

          FIELDS = %i[
            mode
            running
            message
            total_chapters
            pending_jump
            pending_progress
          ].freeze

          DEFAULTS = {
            mode: :read,
            running: true,
            message: nil,
            total_chapters: 0,
            pending_jump: nil,
            pending_progress: nil,
          }.freeze

          module_function

          def contribute(_context = {})
            { PARTITION => DEFAULTS.dup }
          end
        end
      end
    end
  end
end
