# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Requests
        # Immutable movement request for indexed selections.
        SelectionDelta = Data.define(:delta) do
          def initialize(delta:)
            raise ArgumentError, 'delta must be a non-zero Integer' unless delta.is_a?(Integer) && !delta.zero?

            super
          end
        end
      end
    end
  end
end
