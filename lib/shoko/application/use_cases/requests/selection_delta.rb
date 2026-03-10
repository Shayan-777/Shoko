# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Requests
        # Immutable movement request for indexed selections.
        class SelectionDelta < Data.define(:delta)
          def initialize(delta:)
            unless delta.is_a?(Integer) && !delta.zero?
              raise ArgumentError, 'delta must be a non-zero Integer'
            end

            super(delta: delta)
          end
        end
      end
    end
  end
end
