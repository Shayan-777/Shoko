# frozen_string_literal: true

module Shoko
  module Core
    module Reading
      # Translates a restore descriptor into the reader-state updates that
      # re-establish a saved reading position after pagination changes.
      #
      # Pure position arithmetic with no I/O, so it sits in the domain where
      # both the runtime adapter (re-entering a book) and the pagination
      # coordinator (finishing a rebuild) can reach it. Both must restore the
      # same fields, including the rule that a missing or nil page index leaves
      # the current position alone.
      module PageRestoreUpdates
        module_function

        # @param restore [Hash] :current_page_index, :clear_pending_progress
        # @return [Hash] state updates to apply
        def build(restore)
          updates = {}
          index = restore[:current_page_index]
          updates[:current_page_index] = index if restore.key?(:current_page_index) && !index.nil?
          updates[:pending_progress] = nil if restore[:clear_pending_progress]
          updates
        end
      end
    end
  end
end
