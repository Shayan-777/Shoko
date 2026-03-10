# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Requests
        # Immutable cursor movement request for editor widgets.
        class CursorMove < Data.define(:direction)
          VALID_DIRECTIONS = %i[left right up down].freeze

          def initialize(direction:)
            unless VALID_DIRECTIONS.include?(direction)
              raise ArgumentError, "direction must be one of #{VALID_DIRECTIONS.join(', ')}"
            end

            super(direction: direction)
          end
        end
      end
    end
  end
end
