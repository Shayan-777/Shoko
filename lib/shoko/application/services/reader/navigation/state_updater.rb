# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Reader
        module Navigation
          # Applies state updates using focused reader state writer ports.
          # Uses hexagonal ports for writing state - no direct state_store access.
          class StateUpdater
            # @param state_writer [Core::Ports::Outbound::ReaderStateWriter] Port for writing state
            def initialize(state_writer)
              @state_writer = state_writer
            end

            def apply(updates)
              return if updates.nil? || updates.empty?

              @state_writer.update_navigation(updates)
            end
          end
        end
      end
    end
  end
end
