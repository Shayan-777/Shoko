# frozen_string_literal: true

require_relative '../../ports/state_writer'

module Shoko
  module Core
    module Services
      module Navigation
        # Applies state updates using the StateWriter port.
        # Uses hexagonal ports for writing state - no direct state_store access.
        class StateUpdater
          # @param state_writer [Core::Ports::StateWriter] Port for writing state
          def initialize(state_writer)
            @state_writer = state_writer
          end

          def apply(updates)
            return if updates.nil? || updates.empty?

            # Convert path-based updates to navigation attrs
            attrs = {}
            updates.each do |path, value|
              key = path.is_a?(Array) ? path.last : path
              attrs[key] = value
            end
            @state_writer.update_navigation(attrs)
          end
        end
      end
    end
  end
end
