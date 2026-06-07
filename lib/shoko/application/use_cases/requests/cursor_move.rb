# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Requests
        VALID_CURSOR_MOVE_DIRECTIONS = %i[left right up down home end].freeze

        # Immutable cursor movement request for editor widgets.
        CursorMove = Data.define(:direction) do
          def initialize(direction:)
            unless VALID_CURSOR_MOVE_DIRECTIONS.include?(direction)
              raise ArgumentError, "direction must be one of #{VALID_CURSOR_MOVE_DIRECTIONS.join(', ')}"
            end

            super
          end
        end
      end
    end
  end
end
