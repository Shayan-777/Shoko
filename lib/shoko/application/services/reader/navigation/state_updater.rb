# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Reader
        module Navigation
          # Applies state updates using focused reader state writer ports.
          # Uses the reader session store rather than state-slice writer ports.
          class StateUpdater
            def initialize(reader_session_store)
              @reader_session_store = reader_session_store
            end

            def apply(updates)
              return if updates.nil? || updates.empty?

              snapshot = @reader_session_store.load
              @reader_session_store.save(snapshot.with(**updates))
            end
          end
        end
      end
    end
  end
end
